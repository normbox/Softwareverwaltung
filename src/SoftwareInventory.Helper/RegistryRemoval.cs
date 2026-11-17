#nullable disable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace SoftwareInventory.Helper
{
    /// <summary>Rohe Werte eines Uninstall-Eintrags, so wie sie in der Registry stehen (Variablen nicht eingesetzt).</summary>
    public sealed class UninstallEntry
    {
        public string DisplayName { get; set; }
        public bool IsMsi { get; set; }
        public string UninstallString { get; set; }
        public string QuietUninstallString { get; set; }
        public string InstallLocation { get; set; }
        public string DisplayIcon { get; set; }
    }

    /// <summary>Grund aus dem Plan des Moduls (Code und Args); übernommen werden nur bekannte Codes.</summary>
    public sealed class BackupReason
    {
        public BackupReason(string code, IEnumerable<object> args)
        {
            Code = code;
            Args = (args ?? new object[0]).Where(a => a is not null).Select(a => Convert.ToString(a, CultureInfo.InvariantCulture)).ToList();
        }

        public string Code { get; }

        public IReadOnlyList<string> Args { get; }
    }

    /// <summary>
    /// Was das Entfernen vom System braucht. Ein Adapter, damit der Ablauf ohne Adminrechte und ohne echte Registry testbar
    /// ist (<c>WindowsRegistryRemovalSystem</c> ist die echte Umsetzung im Helfer).
    /// </summary>
    public interface IRegistryRemovalSystem
    {
        /// <summary>Läuft der Helfer mit Administratorrechten?</summary>
        bool Elevated { get; }

        /// <summary>Für die Verwaist-Prüfung; im Helfer nur mit maschinenweiten Variablen.</summary>
        IOrphanEnvironment Environment { get; }

        /// <summary>Der Ordner für HKLM-Sicherungen (fest, nie aus dem Plan).</summary>
        string BackupFolder { get; }

        DateTime UtcNow { get; }

        /// <summary>Liest den Eintrag in der 64-Bit-Ansicht; null, wenn es den Schlüssel nicht gibt.</summary>
        UninstallEntry ReadEntry(string nativeKey);

        /// <summary>Legt den Ordner (und darüber Program Files\Softwareverwaltung) an, falls er fehlt; Bestand bleibt unberührt.</summary>
        Problem CreateBackupFolderIfMissing();

        /// <summary><see cref="BackupFolderRules.Check"/> für den Ordner.</summary>
        Problem CheckBackupFolder();

        /// <summary>reg.exe export in die Datei; liefert den Exit-Code.</summary>
        int ExportKey(string nativeKey, string file);

        /// <summary>Liest die Datei einmal über ein Handle (<see cref="WindowsBackupFileReader"/>); wirft, wenn das nicht geht.</summary>
        BackupFileRead ReadFile(string path);

        /// <summary>Legt die Datei neu an (scheitert, wenn es sie gibt), mit eigenem Besitzer und geschützter DACL.</summary>
        void WriteNewFile(string path, byte[] bytes);

        /// <summary>Löscht die Datei, wenn es sie gibt; wirft nie.</summary>
        void DeleteFile(string path);

        /// <summary>Löscht den Schlüssel samt Unterschlüsseln in der 64-Bit-Ansicht.</summary>
        void DeleteKey(string nativeKey);

        bool KeyExists(string nativeKey);
    }

    /// <summary>Ergebnis von <see cref="RegistryRemoval.Run"/>: entweder Problem oder entfernt, mit Pfad der Sicherung.</summary>
    public sealed class RegistryRemovalOutcome
    {
        public Problem Problem { get; set; }
        public bool Removed { get; set; }
        public string BackupFile { get; set; }
        public string NativeKey { get; set; }
    }

    /// <summary>
    /// Verwaisten Uninstall-Eintrag unter HKLM sichern und entfernen (Operation RemoveRegistryEntry). Der Helfer glaubt dem
    /// Plan nur Schlüssel, ActionId und Gründe und prüft alles selbst: fester Zweig, sicherer Name, Eintrag neu gelesen, kein
    /// MSI, weiterhin verwaist (nur maschinenweite Variablen), Ordner nur von Administratoren beschreibbar. Die Sicherung
    /// entsteht über eine Zwischendatei im Admin-Ordner; ihre Bytes werden einmal gelesen und geprüft, die endgültige
    /// <c>&lt;ActionId&gt;.reg</c> schreibt der Helfer selbst und prüft sie erneut. Erst dann kommt die Begleitdatei und erst
    /// danach wird der Schlüssel gelöscht. Scheitert etwas vor dem Löschen, bleibt der Schlüssel unberührt und keine
    /// unvollständige Sicherung liegen.
    /// </summary>
    public static class RegistryRemoval
    {
        public const string Scope = "Machine";

        /// <summary>Dieselben Codes wie $script:KnownBackupReasonCodes im Modul (RegistryBackup.ps1).</summary>
        public static readonly string[] KnownReasonCodes = { "OrphanedEntry", "NewerInstallNextTo" };

        public static readonly UninstallLocation[] MachineLocations =
        {
            new UninstallLocation(@"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", Scope),
            new UninstallLocation(@"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall", Scope),
        };

        private static readonly Regex MachineKey = new Regex(
            @"^HKLM:\\SOFTWARE\\(?<wow>WOW6432Node\\)?Microsoft\\Windows\\CurrentVersion\\Uninstall\\(?<name>[^\\]+)$",
            RegexOptions.Compiled | RegexOptions.IgnoreCase);

        private static readonly Regex ActionIdPattern = new Regex(
            "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

        /// <summary>
        /// Prüft, sichert und entfernt. Codes: RemoveEntryNotElevated, RemoveEntryBadActionId, RemoveEntryNotUninstallKey,
        /// BackupKeyNameUnsafe, RemoveEntryKeyUnreadable, RemoveEntryKeyGone, RemoveEntryNotOrphaned (Arg: Grund), die Codes
        /// von <see cref="BackupFolderRules"/> und BackupFolderCreateFailed, RemoveEntryExportFailed (Arg: Exit-Code),
        /// BackupFile* (<see cref="BackupFileRules"/>), BackupFileUnreadable, Backup&lt;Code&gt; aus
        /// <see cref="BackupFileRules.DecodeText"/> und <see cref="RegistryBackupRules.CheckContent"/>, BackupFileMismatch,
        /// RemoveEntryBackupWriteFailed und RemoveEntryDeleteFailed.
        /// </summary>
        public static RegistryRemovalOutcome Run(string registryKey, string actionId, IEnumerable<BackupReason> reasons, IRegistryRemovalSystem system)
        {
            var outcome = new RegistryRemovalOutcome();
            if (!system.Elevated)
            {
                return Fail(outcome, "RemoveEntryNotElevated");
            }
            if (string.IsNullOrEmpty(actionId) || !ActionIdPattern.IsMatch(actionId))
            {
                return Fail(outcome, "RemoveEntryBadActionId");
            }
            var match = MachineKey.Match(registryKey ?? "");
            if (!match.Success)
            {
                return Fail(outcome, "RemoveEntryNotUninstallKey", registryKey ?? "");
            }
            var name = match.Groups["name"].Value;
            if (RegistryBackupRules.HasUnsafeKeyCharacter(name))
            {
                return Fail(outcome, "BackupKeyNameUnsafe");
            }
            var wow = match.Groups["wow"].Success;
            var nativeKey = MachineLocations[wow ? 1 : 0].NativePath + "\\" + name;
            outcome.NativeKey = nativeKey;

            UninstallEntry entry;
            try
            {
                entry = system.ReadEntry(nativeKey);
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException || ex is System.Security.SecurityException)
            {
                return Fail(outcome, "RemoveEntryKeyUnreadable");
            }
            if (entry is null)
            {
                return Fail(outcome, "RemoveEntryKeyGone");
            }
            var notOrphaned = OrphanRules.Check(entry.IsMsi, entry.UninstallString, entry.QuietUninstallString, entry.InstallLocation, entry.DisplayIcon, wow ? "X86" : null, system.Environment);
            if (notOrphaned is not null)
            {
                return Fail(outcome, "RemoveEntryNotOrphaned", notOrphaned);
            }

            var folderProblem = system.CreateBackupFolderIfMissing() ?? system.CheckBackupFolder();
            if (folderProblem is not null)
            {
                outcome.Problem = folderProblem;
                return outcome;
            }

            var id = actionId.ToLowerInvariant();
            var staged = Path.Combine(system.BackupFolder, id + ".tmp");
            var final = Path.Combine(system.BackupFolder, id + ".reg");
            var sidecar = Path.Combine(system.BackupFolder, id + ".json");
            var backupProblem = WriteBackup(system, nativeKey, staged, final, sidecar, entry.DisplayName ?? name, id, reasons);
            if (backupProblem is not null)
            {
                outcome.Problem = backupProblem;
                return outcome;
            }
            outcome.BackupFile = final;

            try
            {
                system.DeleteKey(nativeKey);
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException || ex is System.Security.SecurityException || ex is ArgumentException)
            {
                // Die Sicherung bleibt: Sie beschreibt den Schlüssel, wie er war, und schadet nicht.
                return Fail(outcome, "RemoveEntryDeleteFailed", ex.GetType().Name);
            }
            if (system.KeyExists(nativeKey))
            {
                return Fail(outcome, "RemoveEntryDeleteFailed", "");
            }
            outcome.Removed = true;
            return outcome;
        }

        /// <summary>
        /// Sicherung schreiben und prüfen. Bei einem Problem werden nur Dateien gelöscht, die dieser Lauf selbst angelegt hat:
        /// Gibt es <c>&lt;ActionId&gt;.reg</c> oder <c>.json</c> schon (eine wiederverwendete ActionId), scheitert das Anlegen,
        /// und die vorhandene Sicherung bleibt unberührt.
        /// </summary>
        private static Problem WriteBackup(IRegistryRemovalSystem system, string nativeKey, string staged, string final, string sidecar, string displayName, string id, IEnumerable<BackupReason> reasons)
        {
            var createdFinal = false;
            var createdSidecar = false;
            Problem problem = null;
            try
            {
                var exit = system.ExportKey(nativeKey, staged);
                if (exit != 0)
                {
                    return problem = new Problem("RemoveEntryExportFailed", exit);
                }
                problem = ReadChecked(system, staged, true, nativeKey, out var bytes);
                if (problem is not null)
                {
                    return problem;
                }
                try
                {
                    system.WriteNewFile(final, bytes);
                    createdFinal = true;
                }
                catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException)
                {
                    return problem = new Problem("RemoveEntryBackupWriteFailed", final);
                }
                problem = ReadChecked(system, final, false, nativeKey, out var check);
                if (problem is not null)
                {
                    return problem;
                }
                if (!check.SequenceEqual(bytes))
                {
                    return problem = new Problem("BackupFileMismatch", final);
                }
                try
                {
                    system.WriteNewFile(sidecar, BuildSidecar(id, displayName, nativeKey, system.UtcNow, reasons));
                    createdSidecar = true;
                }
                catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException)
                {
                    return problem = new Problem("RemoveEntryBackupWriteFailed", sidecar);
                }
                return null;
            }
            finally
            {
                system.DeleteFile(staged);
                if (problem is not null)
                {
                    if (createdSidecar)
                    {
                        system.DeleteFile(sidecar);
                    }
                    if (createdFinal)
                    {
                        system.DeleteFile(final);
                    }
                }
            }
        }

        /// <summary>Datei einmal lesen und prüfen: Datei selbst, Kodierung und Inhalt. Die Bytes stammen aus demselben Lesevorgang.</summary>
        private static Problem ReadChecked(IRegistryRemovalSystem system, string path, bool staged, string nativeKey, out byte[] bytes)
        {
            bytes = null;
            BackupFileRead read;
            try
            {
                read = system.ReadFile(path);
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException || ex is InvalidOperationException || ex is System.Security.SecurityException || ex is ArgumentException)
            {
                return new Problem("BackupFileUnreadable", path);
            }
            var fileProblem = staged ? BackupFileRules.CheckStagedFile(path, read.Info) : BackupFileRules.CheckFile(path, read.Info);
            if (fileProblem is not null)
            {
                return fileProblem;
            }
            if (read.Bytes is null && read.Size > BackupFileRules.MaxBytes)
            {
                return new Problem("BackupTooLarge");
            }
            var decode = BackupFileRules.DecodeText(read.Bytes, out var text);
            if (decode is not null)
            {
                return BackupProblem(decode);
            }
            var content = RegistryBackupRules.CheckContent(text, nativeKey, Scope, MachineLocations);
            if (content is not null)
            {
                return BackupProblem(content);
            }
            bytes = read.Bytes;
            return null;
        }

        /// <summary>Nur bekannte Codes, höchstens 4 Args mit je höchstens 200 Zeichen; OrphanedEntry steht immer dabei.</summary>
        public static IReadOnlyList<BackupReason> KnownReasons(IEnumerable<BackupReason> reasons)
        {
            var known = (reasons ?? Enumerable.Empty<BackupReason>())
                .Where(r => r is not null && KnownReasonCodes.Contains(r.Code, StringComparer.Ordinal))
                .Select(r => new BackupReason(r.Code, r.Args.Take(4).Select(a => (object)(a.Length > 200 ? a.Substring(0, 200) : a))))
                .ToList();
            if (!known.Any(r => r.Code == "OrphanedEntry"))
            {
                known.Insert(0, new BackupReason("OrphanedEntry", null));
            }
            return known;
        }

        /// <summary>Begleitdatei im Format des Moduls (Write-RegistryBackupSidecar, SchemaVersion 1), UTF-8 ohne BOM.</summary>
        public static byte[] BuildSidecar(string actionId, string name, string nativeKey, DateTime createdUtc, IEnumerable<BackupReason> reasons)
        {
            var json = new StringBuilder();
            json.Append("{\r\n");
            json.Append("  \"SchemaVersion\": 1,\r\n");
            json.Append("  \"ActionId\": ").Append(Quote(actionId)).Append(",\r\n");
            json.Append("  \"CreatedAt\": ").Append(Quote(createdUtc.ToUniversalTime().ToString("o", CultureInfo.InvariantCulture))).Append(",\r\n");
            json.Append("  \"Name\": ").Append(Quote(name)).Append(",\r\n");
            json.Append("  \"NativeKey\": ").Append(Quote(nativeKey)).Append(",\r\n");
            json.Append("  \"Scope\": ").Append(Quote(Scope)).Append(",\r\n");
            json.Append("  \"Reasons\": [");
            var first = true;
            foreach (var reason in KnownReasons(reasons))
            {
                json.Append(first ? "\r\n" : ",\r\n");
                first = false;
                json.Append("    { \"Code\": ").Append(Quote(reason.Code)).Append(", \"Args\": [");
                json.Append(string.Join(", ", reason.Args.Select(Quote)));
                json.Append("] }");
            }
            json.Append(first ? "]\r\n" : "\r\n  ]\r\n");
            json.Append("}\r\n");
            return new UTF8Encoding(false).GetBytes(json.ToString());
        }

        /// <summary>JSON-Zeichenkette; Steuerzeichen, Zeilentrenner und alles außerhalb von ASCII als Escape-Folge.</summary>
        private static string Quote(string value)
        {
            var text = new StringBuilder("\"");
            foreach (var c in value ?? "")
            {
                if (c == '"' || c == '\\')
                {
                    text.Append('\\').Append(c);
                }
                else if (c < ' ' || c > '~')
                {
                    text.Append('\\').Append('u').Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                }
                else
                {
                    text.Append(c);
                }
            }
            return text.Append('"').ToString();
        }

        /// <summary>Prüfcode der .reg-Prüfung mit Präfix (BackupBadHeader …), damit die vorhandenen Texte des Moduls greifen.</summary>
        private static Problem BackupProblem(string code) => new Problem(BackupPrefix + code);

        private const string BackupPrefix = "Backup";

        private static RegistryRemovalOutcome Fail(RegistryRemovalOutcome outcome, string code, params object[] args)
        {
            outcome.Problem = new Problem(code, args);
            outcome.Removed = false;
            return outcome;
        }
    }
}
