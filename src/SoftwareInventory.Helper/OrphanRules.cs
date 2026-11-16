#nullable disable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace SoftwareInventory.Helper
{
    /// <summary>
    /// Was die Verwaist-Prüfung vom System wissen muss. Ein Adapter, damit sie ohne echtes Dateisystem testbar ist
    /// (<see cref="WindowsOrphanEnvironment"/> ist die echte Umsetzung).
    /// </summary>
    public interface IOrphanEnvironment
    {
        /// <summary>Umgebungsvariablen wie %ProgramFiles% einsetzen.</summary>
        string ExpandVariables(string text);

        /// <summary>Gibt es die Datei oder den Ordner (Test-Path -LiteralPath)?</summary>
        bool PathExists(string path);

        /// <summary>Gibt es die Datei (Test-Path -PathType Leaf)?</summary>
        bool FileExists(string path);

        /// <summary>Ist die Wurzel (z. B. C:\) erreichbar?</summary>
        bool RootReachable(string root);

        /// <summary>Art des Laufwerks zu einer Wurzel (Fixed, Network, Removable, CDRom, ...); null, wenn unbekannt.</summary>
        string DriveType(string root);

        /// <summary>Liegt der Pfad im Profil eines Benutzers (C:\Users\...)? Dort sieht ein erhöhter Helfer unter Umständen ein anderes Profil.</summary>
        bool IsUserProfilePath(string path);

        /// <summary>System32, SysWOW64 und der Windows-Ordner.</summary>
        IReadOnlyList<string> SystemFolders { get; }

        /// <summary>System32: Befehle ohne Pfad werden dort gesucht (nie über PATH).</summary>
        string SystemFolder { get; }
    }

    public enum PathState
    {
        Unknown,
        Missing,
        Exists,
    }

    /// <summary>
    /// Ist ein Uninstall-Eintrag nur noch ein Rest ohne Programm? Dieselben Regeln wie Test-OrphanedRegistryEntry im Modul
    /// (Get-RegistrySoftware.ps1); beide prüfen gegen tests/Data/registry-orphan-cases.json.
    /// Verwaist nur, wenn die Datei im Deinstallationsbefehl fehlt (der UninstallString ist Pflicht, ein QuietUninstallString
    /// wird zusätzlich geprüft, wenn es ihn gibt) und InstallLocation sowie DisplayIcon fehlen oder ins Leere zeigen.
    /// Nie verwaist: MSI-Einträge, Einträge ohne UninstallString, nicht auswertbare Befehle, Systemwerkzeuge, Netzwerkpfade,
    /// nicht erreichbare Laufwerke und Laufwerke, die keine festen lokalen sind. Was sich nicht sicher beurteilen lässt
    /// (Unknown), zählt wie „vorhanden“: Der Helfer lehnt ab.
    /// </summary>
    public static class OrphanRules
    {
        private const StringComparison IgnoreCase = StringComparison.OrdinalIgnoreCase;

        /// <summary>
        /// null, wenn der Eintrag verwaist ist; sonst der Grund, warum nicht: Msi, NoUninstallString, CommandUnparseable,
        /// SystemPath, PathExists oder PathUnknown.
        /// </summary>
        public static string Check(bool isMsi, string uninstallString, string quietUninstallString, string installLocation, string displayIcon, IOrphanEnvironment env)
        {
            try
            {
                if (isMsi)
                {
                    return "Msi";
                }
                var uninstall = NullIfEmpty(uninstallString);
                if (uninstall is null)
                {
                    return "NoUninstallString";
                }
                var commands = new List<string> { uninstall };
                var quiet = NullIfEmpty(quietUninstallString);
                if (quiet is not null)
                {
                    commands.Add(quiet);
                }
                var system = env.SystemFolders.Where(f => !string.IsNullOrEmpty(f)).Select(f => f.TrimEnd('\\') + "\\").ToList();
                foreach (var command in commands)
                {
                    var filePath = SplitFilePath(command, env);
                    if (string.IsNullOrEmpty(filePath))
                    {
                        return "CommandUnparseable";
                    }
                    if (system.Any(s => filePath.StartsWith(s, IgnoreCase)))
                    {
                        return "SystemPath";
                    }
                    var state = GetPathState(filePath, env);
                    if (state != PathState.Missing)
                    {
                        return state == PathState.Exists ? "PathExists" : "PathUnknown";
                    }
                }
                foreach (var path in new[] { NullIfEmpty(installLocation), ConvertFromDisplayIcon(displayIcon, env) })
                {
                    if (string.IsNullOrWhiteSpace(path))
                    {
                        continue;
                    }
                    var state = GetPathState(path, env);
                    if (state != PathState.Missing)
                    {
                        return state == PathState.Exists ? "PathExists" : "PathUnknown";
                    }
                }
                return null;
            }
            catch (ArgumentException)
            {
                // Ungültige Zeichen im Pfad: nicht auswertbar, also nicht verwaist.
                return "CommandUnparseable";
            }
            catch (NotSupportedException)
            {
                return "CommandUnparseable";
            }
        }

        /// <summary>Exists, Missing oder Unknown für einen Pfad aus der Registry (Anführungszeichen und Umgebungsvariablen erlaubt).</summary>
        public static PathState GetPathState(string path, IOrphanEnvironment env)
        {
            if (string.IsNullOrWhiteSpace(path))
            {
                return PathState.Unknown;
            }
            var p = env.ExpandVariables(path.Trim().Trim('"').Trim());
            if (string.IsNullOrEmpty(p) || p.StartsWith("\\\\", StringComparison.Ordinal) || !Path.IsPathRooted(p))
            {
                return PathState.Unknown;
            }
            var root = Path.GetPathRoot(p);
            if (string.IsNullOrEmpty(root) || !env.RootReachable(root) || env.DriveType(root) != "Fixed")
            {
                return PathState.Unknown;
            }
            if (env.IsUserProfilePath(p))
            {
                return PathState.Unknown;
            }
            return env.PathExists(p) ? PathState.Exists : PathState.Missing;
        }

        /// <summary>Datei im Befehl (wie Split-CommandLine im Modul): mit Anführungszeichen bis zum nächsten, sonst bis zur .exe; null, wenn nicht auswertbar.</summary>
        public static string SplitFilePath(string commandLine, IOrphanEnvironment env)
        {
            var text = (commandLine ?? "").Trim();
            if (text.Length == 0)
            {
                return null;
            }
            if (text.StartsWith("\"", StringComparison.Ordinal))
            {
                var end = text.IndexOf('"', 1);
                return end < 2 ? null : env.ExpandVariables(text.Substring(1, end - 1));
            }

            var candidates = new List<int>();
            var index = 0;
            while (index >= 0)
            {
                index = text.IndexOf(' ', index + 1);
                var cut = index < 0 ? text.Length : index;
                if (text.Substring(0, cut).EndsWith(".exe", IgnoreCase))
                {
                    candidates.Add(cut);
                }
            }
            if (candidates.Count == 0)
            {
                return null;
            }
            var chosen = candidates[0];
            foreach (var cut in candidates)
            {
                if (env.FileExists(ResolveCommandPath(env.ExpandVariables(text.Substring(0, cut)), env)))
                {
                    chosen = cut;
                    break;
                }
            }
            return ResolveCommandPath(env.ExpandVariables(text.Substring(0, chosen)), env);
        }

        /// <summary>Pfade ohne Wurzel werden an System32 gehängt, nie über PATH gesucht.</summary>
        public static string ResolveCommandPath(string path, IOrphanEnvironment env) =>
            Path.IsPathRooted(path) ? path : Path.Combine(env.SystemFolder, path);

        public static string NullIfEmpty(string value)
        {
            if (value is null)
            {
                return null;
            }
            var text = value.Trim();
            return text.Length > 0 ? text : null;
        }

        /// <summary>"C:\Programme\App\app.exe",0 wird zu C:\Programme\App\app.exe.</summary>
        public static string ConvertFromDisplayIcon(string value, IOrphanEnvironment env)
        {
            var text = NullIfEmpty(value);
            if (text is null)
            {
                return null;
            }
            text = Regex.Replace(text, @",\s*-?\d+$", "").Trim('"', ' ');
            return env.ExpandVariables(text);
        }
    }
}
