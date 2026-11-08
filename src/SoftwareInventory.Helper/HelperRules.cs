#nullable disable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace SoftwareInventory.Helper
{
    /// <summary>Grund, warum etwas nicht ausgeführt wird: Code und Args, den Text bildet das Modul.</summary>
    public sealed class Problem
    {
        public Problem(string code, params object[] args)
        {
            Code = code;
            Args = args;
        }

        public string Code { get; }

        public object[] Args { get; }
    }

    /// <summary>Systemordner als Werte, damit die Regeln ohne echtes System testbar sind.</summary>
    public sealed class HelperPaths
    {
        public string ProgramFiles { get; set; }
        public string SystemDrive { get; set; }
        public string Windows { get; set; }
        public string TempPath { get; set; }
        public string System32 { get; set; }
        public Func<string, bool> FileExists { get; set; }

        public static HelperPaths Current() => new HelperPaths
        {
            ProgramFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            SystemDrive = Path.GetPathRoot(Environment.SystemDirectory).TrimEnd('\\'),
            Windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            TempPath = Path.GetTempPath(),
            System32 = Environment.SystemDirectory,
            FileExists = File.Exists,
        };
    }

    /// <summary>Letzte Prüfungen, die der Helfer selbst vornimmt. Dem Plan wird nicht blind geglaubt.</summary>
    public static class HelperRules
    {
        private const StringComparison IgnoreCase = StringComparison.OrdinalIgnoreCase;

        private static readonly Regex Space = new Regex(@"\s+", RegexOptions.Compiled);
        private static readonly Regex WingetArguments = new Regex(@"^(upgrade|uninstall) --id \S", RegexOptions.Compiled);
        private static readonly Regex MsiArguments = new Regex(@"^/x \{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\} /qn /norestart$", RegexOptions.Compiled | RegexOptions.IgnoreCase);
        private static readonly Regex UninstallKey = new Regex(@"^HKLM:\\SOFTWARE\\(WOW6432Node\\)?Microsoft\\Windows\\CurrentVersion\\Uninstall\\[^\\]+$", RegexOptions.Compiled | RegexOptions.IgnoreCase);
        private static readonly Regex BarOnly = new Regex(@"^[\s\-\\|/█▒]*$", RegexOptions.Compiled);
        private static readonly Regex BarLine = new Regex(@"^\s*[█▒]+\s", RegexOptions.Compiled);

        /// <summary>winget nur aus WindowsApps; erhöht nichts aus Benutzer- oder Temp-Ordnern.</summary>
        public static Problem CheckFilePath(string filePath, bool elevated, HelperPaths paths)
        {
            if (string.IsNullOrEmpty(filePath) || !Path.IsPathRooted(filePath))
            {
                return new Problem("HelperPathNotAbsolute");
            }
            var full = Path.GetFullPath(filePath);
            if (string.Equals(Path.GetFileName(full), "winget.exe", IgnoreCase))
            {
                var apps = Path.Combine(paths.ProgramFiles, "WindowsApps").TrimEnd('\\') + "\\";
                return full.StartsWith(apps, IgnoreCase) && paths.FileExists(full) ? null : new Problem("HelperWingetNotFound", full);
            }
            if (elevated)
            {
                var blocked = new[] { paths.SystemDrive + "\\Users", Path.Combine(paths.Windows, "Temp"), paths.TempPath };
                if (blocked.Any(root => full.StartsWith(root.TrimEnd('\\') + "\\", IgnoreCase)))
                {
                    return new Problem("HelperPathInUserFolder", full);
                }
            }
            return paths.FileExists(full) ? null : new Problem("HelperFileNotFound", full);
        }

        /// <summary>
        /// Erhöht wird nur ausgeführt, was der Helfer selbst bestätigen kann: winget und msiexec in fester
        /// Form, Deinstallationsbefehle nur, wenn sie genau so im Schlüssel unter HKLM stehen. Ohne
        /// Erhöhung gilt das nicht, denn dann hat der Aufrufer ohnehin dieselben Rechte.
        /// </summary>
        public static Problem CheckCommand(string method, string filePath, string arguments, string registryKey, bool elevated, HelperPaths paths, Func<string, string, string> readRegistryValue)
        {
            if (!elevated)
            {
                return null;
            }
            var mismatch = new Problem("HelperCommandMismatch");
            var args = arguments ?? "";
            switch (method)
            {
                case "Winget":
                    return string.Equals(Path.GetFileName(filePath), "winget.exe", IgnoreCase) && WingetArguments.IsMatch(args) ? null : mismatch;
                case "Msi":
                    return string.Equals(filePath, Path.Combine(paths.System32, "msiexec.exe"), IgnoreCase) && MsiArguments.IsMatch(args) ? null : mismatch;
                case "QuietUninstallString":
                case "UninstallString":
                    if (string.IsNullOrEmpty(registryKey) || !UninstallKey.IsMatch(registryKey))
                    {
                        return mismatch;
                    }
                    var raw = readRegistryValue(registryKey, method);
                    return CommandMatches(raw, filePath, args, paths) ? null : mismatch;
                default:
                    return mismatch;
            }
        }

        /// <summary>Stimmt der Befehl mit dem Registry-Wert überein? Anführungszeichen und Leerraum zählen nicht.</summary>
        public static bool CommandMatches(string rawCommand, string filePath, string arguments, HelperPaths paths)
        {
            if (string.IsNullOrWhiteSpace(rawCommand) || string.IsNullOrEmpty(filePath))
            {
                return false;
            }
            var actual = Normalize(Environment.ExpandEnvironmentVariables(rawCommand));
            var candidates = new List<string> { filePath };
            // Registry-Wert ohne Ordner (MsiExec.exe /X…): Das Modul sucht solche Programme nur in System32.
            if (string.Equals(Path.GetDirectoryName(filePath), paths.System32.TrimEnd('\\'), IgnoreCase))
            {
                candidates.Add(Path.GetFileName(filePath));
            }
            return candidates.Any(c => string.Equals(actual, Normalize(Environment.ExpandEnvironmentVariables(c + " " + arguments)), IgnoreCase));
        }

        private static string Normalize(string text) => Space.Replace(text.Replace("\"", ""), " ").Trim();

        /// <summary>Letzte Zeilen ohne Fortschrittsanzeigen (winget zeichnet Balken und Drehstriche mit \r).</summary>
        public static string OutputTail(string text, int lines = 50)
        {
            if (string.IsNullOrEmpty(text))
            {
                return null;
            }
            var clean = new List<string>();
            foreach (var line in Regex.Split(text, "\r\n|\n"))
            {
                var last = line.Split('\r').LastOrDefault(part => part.Trim().Length > 0);
                if (last == null)
                {
                    continue;
                }
                var trimmed = last.TrimEnd();
                if (BarOnly.IsMatch(trimmed) || BarLine.IsMatch(trimmed))
                {
                    continue;
                }
                clean.Add(trimmed);
            }
            return string.Join("\n", clean.Skip(Math.Max(0, clean.Count - lines)));
        }
    }

    /// <summary>Der laufende Prozess, soweit das Abbrechen ihn braucht.</summary>
    public interface ICancelTarget
    {
        int Id { get; }

        void Kill();

        bool WaitForExit(int milliseconds);
    }

    public static class CancelRules
    {
        public const string Stopped = "Stopped";
        public const string Continuing = "Continuing";
        public const string Orphaned = "Orphaned";

        /// <summary>
        /// Bricht ab, wenn das ohne halbe Installation geht: Nur winget wird beendet, und nur solange es
        /// noch keinen Installer gestartet hat. Installer selbst werden nie beendet.
        /// </summary>
        public static string Request(string filePath, ICancelTarget process, Func<int, IEnumerable<string>> childNames)
        {
            if (!string.Equals(Path.GetFileName(filePath), "winget.exe", StringComparison.OrdinalIgnoreCase))
            {
                return Continuing;
            }
            try
            {
                if (HasInstaller(childNames(process.Id)))
                {
                    return Continuing;
                }
                process.Kill();
                process.WaitForExit(5000);
                if (HasInstaller(childNames(process.Id)))
                {
                    return Orphaned;
                }
            }
            catch (Exception)
            {
                return Continuing;
            }
            return Stopped;
        }

        // conhost.exe gehört zu jedem Konsolenprogramm und ist kein Installer.
        private static bool HasInstaller(IEnumerable<string> names) =>
            names.Any(n => !string.Equals(n, "conhost.exe", StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>Fehler der Wiederherstellungspunkt-Schnittstelle mit ihren Fehlercodes.</summary>
    public sealed class RestorePointApiException : Exception
    {
        public RestorePointApiException(string message, IEnumerable<int> codes) : base(message)
        {
            Codes = codes.ToArray();
        }

        public int[] Codes { get; }
    }

    public interface IRestorePointApi
    {
        long LatestSequence();

        long Create(string description, uint type);

        bool ProtectionDisabled();
    }

    public sealed class RestorePointOutcome
    {
        public RestorePointOutcome(string status, string code, params object[] args)
        {
            Status = status;
            Code = code;
            Args = args;
        }

        public string Status { get; }
        public string Code { get; }
        public object[] Args { get; }
    }

    public static class RestorePointRules
    {
        // 1058/1068 als Win32-Code und als HRESULT (0x80070422, 0x8007042C): Dienst deaktiviert bzw. Abhängigkeit fehlt.
        private static readonly int[] Unavailable = { 1058, 1068, -2147023838, -2147023828 };

        /// <summary>Legt einen Wiederherstellungspunkt an und meldet ehrlich, was passiert ist.</summary>
        public static RestorePointOutcome Run(IRestorePointApi api, string description, uint type)
        {
            long before;
            try
            {
                before = api.LatestSequence();
            }
            catch (Exception ex)
            {
                return new RestorePointOutcome("NotAvailable", "RestorePointServiceUnavailable", ex.Message);
            }

            long code;
            try
            {
                code = api.Create(description, type);
            }
            catch (RestorePointApiException ex)
            {
                if (ex.Codes.Intersect(Unavailable).Any())
                {
                    return new RestorePointOutcome("NotAvailable", "RestorePointProtectionOffDetail", ex.Message);
                }
                var hex = string.Join(", ", ex.Codes.Select(c => "0x" + c.ToString("X8")));
                return new RestorePointOutcome("Failed", "RestorePointFailedDetail", ex.Message, hex);
            }

            if (Unavailable.Contains((int)code))
            {
                return new RestorePointOutcome("NotAvailable", "RestorePointProtectionOff");
            }
            if (code != 0)
            {
                return new RestorePointOutcome("Failed", "RestorePointFailedCode", code);
            }

            long after;
            try
            {
                after = api.LatestSequence();
            }
            catch (Exception)
            {
                after = before;
            }
            if (after > before)
            {
                return new RestorePointOutcome("Created", "RestorePointCreatedNumber", after);
            }
            return api.ProtectionDisabled()
                ? new RestorePointOutcome("NotAvailable", "RestorePointProtectionDisabled")
                : new RestorePointOutcome("Skipped", "RestorePointNotCreated");
        }
    }
}
