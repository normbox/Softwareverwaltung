#nullable disable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace SoftwareInventory.Helper
{
    /// <summary>Angaben aus einer Begleitdatei (&lt;Id&gt;.json), so wie sie gelesen wurden; geprüft wird in <see cref="RegistryBackupStore"/>.</summary>
    public sealed class BackupSidecar
    {
        public int SchemaVersion { get; set; }
        public string ActionId { get; set; }
        public string NativeKey { get; set; }
        public string Scope { get; set; }
    }

    /// <summary>Eine Datei im Sicherungsordner (nur die oberste Ebene).</summary>
    public sealed class BackupFolderEntry
    {
        public string Name { get; set; }
        public bool IsDirectory { get; set; }
        public bool IsReparsePoint { get; set; }
        public DateTime LastWriteUtc { get; set; }
    }

    /// <summary>Was das Zurückspielen, Löschen und Bereinigen von HKLM-Sicherungen vom System braucht (Adapter für Tests).</summary>
    public interface IRegistryBackupSystem
    {
        bool Elevated { get; }

        /// <summary>Der Ordner für HKLM-Sicherungen (fest, nie aus dem Plan).</summary>
        string BackupFolder { get; }

        DateTime UtcNow { get; }

        bool BackupFolderExists();

        /// <summary>Ordnerregeln einschließlich OWNER-RIGHTS-Eintrag (wie bei RemoveRegistryEntry).</summary>
        Problem CheckBackupFolder();

        /// <summary>Liest die Datei einmal über ein Handle; wirft FileNotFoundException, wenn es sie nicht gibt.</summary>
        BackupFileRead ReadFile(string path);

        /// <summary>Liest und prüft die Begleitdatei wie eine Sicherungsdatei (Besitzer, Schreibrechte, Link); wirft wie <see cref="ReadFile"/>.</summary>
        BackupSidecar ReadSidecar(string path, out Problem fileProblem);

        void WriteNewFile(string path, byte[] bytes);

        void DeleteFile(string path);

        bool FileExists(string path);

        /// <summary>reg.exe import der Datei in der 64-Bit-Ansicht; liefert den Exit-Code.</summary>
        int ImportFile(string path);

        bool KeyExists(string nativeKey);

        IReadOnlyList<BackupFolderEntry> ListFolder();
    }

    /// <summary>Ergebnis einer Sicherungs-Operation des Helfers.</summary>
    public sealed class BackupStoreOutcome
    {
        public Problem Problem { get; set; }
        public bool Done { get; set; }
        public string NativeKey { get; set; }
        public int Deleted { get; set; }

        /// <summary>Eine eigene Zwischendatei, die sich nicht löschen ließ (räumt die Bereinigung später).</summary>
        public string LeftOver { get; set; }
    }

    /// <summary>
    /// HKLM-Sicherungen im Admin-Ordner zurückspielen, löschen und nach 365 Tagen bereinigen (Operationen
    /// RestoreRegistryBackup, RemoveRegistryBackup, CleanupRegistryBackups). Dateien werden nur über die feste Ordnerangabe
    /// und die Kennung (GUID) gefunden, nie über einen Pfad aus dem Plan; Frist und Ordner stehen fest im Helfer.
    /// </summary>
    public static class RegistryBackupStore
    {
        /// <summary>Aufbewahrungsfrist der Sicherungen (wie $script:RegistryBackupRetentionDays im Modul).</summary>
        public const int RetentionDays = 365;

        /// <summary>Eine Begleitdatei ohne Sicherung gilt nach dieser Zeit als Rest.</summary>
        public static readonly TimeSpan OrphanSidecarAge = TimeSpan.FromDays(1);

        /// <summary>Zwischendateien (.tmp, .import.reg) gibt es nur während eines Laufs; danach sind sie Reste.</summary>
        public static readonly TimeSpan TempFileAge = TimeSpan.FromHours(1);

        private static readonly Regex Id = new Regex(@"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z", RegexOptions.Compiled | RegexOptions.IgnoreCase);

        private static readonly Regex FileName = new Regex(
            @"^(?<id>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.(?<ext>reg|json|tmp|import\.reg)\z",
            RegexOptions.Compiled | RegexOptions.IgnoreCase);

        private static readonly string[] OwnExtensions = { ".reg", ".json", ".tmp", ".import.reg" };

        /// <summary>
        /// Spielt die Sicherung &lt;Id&gt;.reg zurück. Codes: BackupNotElevated, BackupBadId, die Ordnercodes,
        /// BackupNotFound, BackupFile*, BackupMetadataMissing, BackupMetadataInvalid, BackupKeyNameUnsafe,
        /// Backup&lt;Code&gt; der Inhaltsprüfung (nur der Schlüssel aus der .json und seine Unterschlüssel unter einem
        /// HKLM-Uninstall-Zweig, keine Löschzeilen), RestoreKeyExists, BackupImportWriteFailed, BackupFileMismatch,
        /// RestoreBackupFailed (Arg: Exit-Code), RestorePartial (Import gescheitert, Schlüssel aber angelegt; Args: Schlüssel,
        /// Exit-Code), RestoreKeyMissing (Exit 0, Schlüssel fehlt trotzdem).
        /// </summary>
        public static BackupStoreOutcome Restore(string id, IRegistryBackupSystem system)
        {
            var outcome = new BackupStoreOutcome();
            var start = Start(id, system, true);
            if (start is not null)
            {
                outcome.Problem = start;
                return outcome;
            }
            id = id.ToLowerInvariant();
            var regPath = Path.Combine(system.BackupFolder, id + ".reg");

            var bytes = ReadChecked(system, regPath, out var readProblem);
            if (readProblem is not null)
            {
                outcome.Problem = readProblem;
                return outcome;
            }
            var decode = BackupFileRules.DecodeText(bytes, out var text);
            if (decode is not null)
            {
                outcome.Problem = new Problem(BackupCode(decode));
                return outcome;
            }

            var sidecarProblem = ReadSidecarChecked(system, Path.Combine(system.BackupFolder, id + ".json"), id, out var nativeKey);
            if (sidecarProblem is not null)
            {
                outcome.Problem = sidecarProblem;
                return outcome;
            }
            outcome.NativeKey = nativeKey;
            // Nur der Schlüssel aus der .json und seine Unterschlüssel, direkt unter einem HKLM-Uninstall-Zweig; keine Löschzeilen.
            var content = RegistryBackupRules.CheckContent(text, nativeKey, RegistryRemoval.Scope, RegistryRemoval.MachineLocations);
            if (content is not null)
            {
                outcome.Problem = new Problem(BackupCode(content));
                return outcome;
            }
            if (system.KeyExists(nativeKey))
            {
                outcome.Problem = new Problem("RestoreKeyExists", nativeKey);
                return outcome;
            }

            // Genau diese Bytes in eine eigene Datei im Admin-Ordner schreiben, erneut lesen und vergleichen, dann importieren.
            var import = Path.Combine(system.BackupFolder, id + ".import.reg");
            var created = false;
            try
            {
                try
                {
                    system.WriteNewFile(import, bytes);
                    created = true;
                }
                catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException)
                {
                    outcome.Problem = new Problem("BackupImportWriteFailed", import);
                    return outcome;
                }
                var check = ReadChecked(system, import, out var importProblem);
                if (importProblem is not null)
                {
                    outcome.Problem = importProblem;
                    return outcome;
                }
                if (!check.SequenceEqual(bytes))
                {
                    outcome.Problem = new Problem("BackupFileMismatch", import);
                    return outcome;
                }
                var exit = system.ImportFile(import);
                var present = system.KeyExists(nativeKey);
                if (exit != 0)
                {
                    // Der Schlüssel war vorher nicht da: Gibt es ihn jetzt, ist er nur teilweise importiert. Nichts automatisch
                    // entfernen; die Meldung nennt den Schlüssel, damit der Benutzer entscheidet.
                    outcome.Problem = present ? new Problem("RestorePartial", nativeKey, exit) : new Problem("RestoreBackupFailed", exit);
                    return outcome;
                }
                if (!present)
                {
                    outcome.Problem = new Problem("RestoreKeyMissing", nativeKey);
                    return outcome;
                }
                outcome.Done = true;
                return outcome;
            }
            finally
            {
                if (created)
                {
                    system.DeleteFile(import);
                    // Hält reg.exe die Datei noch (z. B. nach einem Abbruch), bleibt sie; die Bereinigung entfernt sie nach einer Stunde.
                    if (system.FileExists(import))
                    {
                        outcome.LeftOver = import;
                    }
                }
            }
        }

        /// <summary>
        /// Löscht &lt;Id&gt;.reg, &lt;Id&gt;.json und Reste dieser Kennung. Codes: BackupNotElevated, BackupBadId, die Ordnercodes,
        /// BackupNotFound (es gab keine dieser Dateien), RemoveBackupFailed (Arg: was übrig blieb).
        /// </summary>
        public static BackupStoreOutcome Remove(string id, IRegistryBackupSystem system)
        {
            var outcome = new BackupStoreOutcome();
            var start = Start(id, system, true);
            if (start is not null)
            {
                outcome.Problem = start;
                return outcome;
            }
            id = id.ToLowerInvariant();
            var paths = OwnExtensions.Select(ext => Path.Combine(system.BackupFolder, id + ext)).ToList();
            var present = paths.Where(system.FileExists).ToList();
            if (present.Count == 0)
            {
                outcome.Problem = new Problem("BackupNotFound");
                return outcome;
            }
            foreach (var path in present)
            {
                system.DeleteFile(path);
                outcome.Deleted++;
            }
            var left = paths.Where(system.FileExists).Select(Path.GetFileName).ToList();
            if (left.Count > 0)
            {
                outcome.Deleted -= left.Count;
                outcome.Problem = new Problem("RemoveBackupFailed", string.Join(", ", left));
                return outcome;
            }
            outcome.Done = true;
            return outcome;
        }

        /// <summary>
        /// Löscht abgelaufene Sicherungen (.reg älter als 365 Tage, mit ihrer .json), Begleitdateien ohne Sicherung nach einem
        /// Tag und Zwischendateien nach einer Stunde. Nur Dateien mit eigenem Namensschema auf oberster Ebene; Ordner und Links
        /// bleiben unberührt. Ohne Ordner gibt es nichts zu tun. Codes: BackupNotElevated und die Ordnercodes.
        /// </summary>
        public static BackupStoreOutcome Cleanup(IRegistryBackupSystem system)
        {
            var outcome = new BackupStoreOutcome();
            if (!system.Elevated)
            {
                outcome.Problem = new Problem("BackupNotElevated");
                return outcome;
            }
            if (!system.BackupFolderExists())
            {
                outcome.Done = true;
                return outcome;
            }
            var folderProblem = system.CheckBackupFolder();
            if (folderProblem is not null)
            {
                outcome.Problem = folderProblem;
                return outcome;
            }

            var now = system.UtcNow;
            var entries = system.ListFolder().Where(e => !e.IsDirectory && !e.IsReparsePoint).ToList();
            var parsed = entries
                .Select(e => new { Entry = e, Match = FileName.Match(e.Name ?? "") })
                .Where(x => x.Match.Success)
                .Select(x => new { x.Entry, Id = x.Match.Groups["id"].Value.ToLowerInvariant(), Ext = x.Match.Groups["ext"].Value.ToLowerInvariant() })
                .ToList();
            var regs = parsed.Where(x => x.Ext == "reg").ToDictionary(x => x.Id, x => x.Entry);

            var delete = new List<string>();
            foreach (var item in parsed)
            {
                var age = now - item.Entry.LastWriteUtc;
                switch (item.Ext)
                {
                    case "reg":
                        if (age > TimeSpan.FromDays(RetentionDays))
                        {
                            delete.Add(item.Entry.Name);
                        }
                        break;
                    case "json":
                        // Gehört zur .reg: geht mit ihr. Ohne .reg nur als Rest nach einem Tag.
                        if (regs.TryGetValue(item.Id, out var reg) ? now - reg.LastWriteUtc > TimeSpan.FromDays(RetentionDays) : age > OrphanSidecarAge)
                        {
                            delete.Add(item.Entry.Name);
                        }
                        break;
                    default:
                        if (age > TempFileAge)
                        {
                            delete.Add(item.Entry.Name);
                        }
                        break;
                }
            }
            foreach (var name in delete)
            {
                var path = Path.Combine(system.BackupFolder, name);
                system.DeleteFile(path);
                if (!system.FileExists(path))
                {
                    outcome.Deleted++;
                }
            }
            outcome.Done = true;
            return outcome;
        }

        private static Problem Start(string id, IRegistryBackupSystem system, bool folderRequired)
        {
            if (!system.Elevated)
            {
                return new Problem("BackupNotElevated");
            }
            if (string.IsNullOrEmpty(id) || !Id.IsMatch(id))
            {
                return new Problem("BackupBadId");
            }
            if (folderRequired && !system.BackupFolderExists())
            {
                return new Problem("BackupNotFound");
            }
            return system.CheckBackupFolder();
        }

        /// <summary>Datei einmal lesen und als Sicherungsdatei prüfen (Link, Hardlinks, Besitzer, Schreibrechte).</summary>
        private static byte[] ReadChecked(IRegistryBackupSystem system, string path, out Problem problem)
        {
            problem = null;
            BackupFileRead read;
            try
            {
                read = system.ReadFile(path);
            }
            catch (FileNotFoundException)
            {
                problem = new Problem("BackupNotFound");
                return null;
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException || ex is InvalidOperationException || ex is System.Security.SecurityException || ex is ArgumentException)
            {
                problem = new Problem("BackupFileUnreadable", path);
                return null;
            }
            problem = BackupFileRules.CheckFile(path, read.Info);
            if (problem is not null)
            {
                return null;
            }
            if (read.Bytes is null)
            {
                problem = new Problem(read.Size > BackupFileRules.MaxBytes ? "BackupTooLarge" : "BackupEmpty");
                return null;
            }
            return read.Bytes;
        }

        /// <summary>Begleitdatei lesen und prüfen: SchemaVersion 1, Kennung wie der Dateiname, Bereich Machine, sicherer Schlüsselname.</summary>
        private static Problem ReadSidecarChecked(IRegistryBackupSystem system, string path, string id, out string nativeKey)
        {
            nativeKey = null;
            BackupSidecar sidecar;
            Problem fileProblem;
            try
            {
                sidecar = system.ReadSidecar(path, out fileProblem);
            }
            catch (FileNotFoundException)
            {
                return new Problem("BackupMetadataMissing");
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException || ex is InvalidOperationException || ex is System.Security.SecurityException || ex is ArgumentException)
            {
                return new Problem("BackupMetadataInvalid");
            }
            if (fileProblem is not null)
            {
                return fileProblem;
            }
            if (sidecar is null || sidecar.SchemaVersion != 1 || !string.Equals(sidecar.ActionId, id, StringComparison.OrdinalIgnoreCase)
                || !string.Equals(sidecar.Scope, RegistryRemoval.Scope, StringComparison.Ordinal) || string.IsNullOrEmpty(sidecar.NativeKey))
            {
                return new Problem("BackupMetadataInvalid");
            }
            var leaf = sidecar.NativeKey.Substring(sidecar.NativeKey.LastIndexOf('\\') + 1);
            if (RegistryBackupRules.HasUnsafeKeyCharacter(leaf))
            {
                return new Problem("BackupKeyNameUnsafe");
            }
            nativeKey = sidecar.NativeKey;
            return null;
        }

        private static string BackupCode(string code) => "Backup" + code;
    }
}
