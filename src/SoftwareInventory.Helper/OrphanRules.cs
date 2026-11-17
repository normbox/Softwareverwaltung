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
        /// <summary>
        /// Umgebungsvariablen wie %ProgramFiles% einsetzen. null, wenn der Text eine Variable enthält, die sich nicht sicher
        /// einsetzen lässt (im erhöhten Helfer jede außer den maschinenweiten): Der Pfad gilt dann als nicht auswertbar.
        /// </summary>
        string ExpandVariables(string text);

        /// <summary>
        /// Gibt es die Datei oder den Ordner? Nur „nicht gefunden“ ist Missing; Zugriff verweigert und andere Fehler sind Unknown.
        /// </summary>
        PathState PathStatus(string path);

        /// <summary>Wurzel des Systemlaufwerks (z. B. C:\): nur dort lässt sich „fehlt“ sicher beurteilen.</summary>
        string SystemDriveRoot { get; }

        /// <summary>Die 64-Bit-Programmordner (ProgramW6432, CommonProgramW6432); bei 32-Bit-Einträgen lösen Variablen dort falsch auf.</summary>
        IReadOnlyList<string> NativeProgramFolders { get; }

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
    /// nicht erreichbare Laufwerke, alle Laufwerke außer dem Systemlaufwerk, Pfade ohne Wurzel X:\, Pfade mit verweigertem
    /// Zugriff und bei 32-Bit-Einträgen Pfade unter dem 64-Bit-Programmordner. Was sich nicht sicher beurteilen lässt
    /// (Unknown), zählt wie „vorhanden“: Der Helfer lehnt ab.
    /// </summary>
    public static class OrphanRules
    {
        private const StringComparison IgnoreCase = StringComparison.OrdinalIgnoreCase;

        /// <summary>Pfade ab dieser Länge sind Unknown (Get-PathState im Modul nutzt denselben Wert).</summary>
        public const int MaxPath = 260;

        /// <summary>
        /// null, wenn der Eintrag verwaist ist; sonst der Grund, warum nicht: Msi, NoUninstallString, CommandUnparseable,
        /// SystemPath, PathExists oder PathUnknown.
        /// </summary>
        public static string Check(bool isMsi, string uninstallString, string quietUninstallString, string installLocation, string displayIcon, IOrphanEnvironment env) =>
            Check(isMsi, uninstallString, quietUninstallString, installLocation, displayIcon, null, env);

        /// <summary>Wie oben; <paramref name="architecture"/> ist X86 für Einträge unter WOW6432Node (sonst beliebig oder null).</summary>
        public static string Check(bool isMsi, string uninstallString, string quietUninstallString, string installLocation, string displayIcon, string architecture, IOrphanEnvironment env)
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
                    var state = GetPathState(filePath, architecture, env);
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
                    var state = GetPathState(path, architecture, env);
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

        /// <summary>
        /// Exists, Missing oder Unknown für einen Pfad aus der Registry (Anführungszeichen und Umgebungsvariablen erlaubt).
        /// Unknown: leer, Netzwerkpfad, Wurzel nicht der Form X:\ (auch C:datei.exe, \datei.exe, \\?\...), Laufwerk nicht
        /// erreichbar oder nicht das feste Systemlaufwerk (ein zweites festes Laufwerk kann eine externe USB-Platte sein),
        /// Profilpfad (im erhöhten Helfer), Zugriff verweigert und bei 32-Bit-Einträgen Pfade unter dem 64-Bit-Programmordner.
        /// </summary>
        public static PathState GetPathState(string path, string architecture, IOrphanEnvironment env)
        {
            if (string.IsNullOrWhiteSpace(path))
            {
                return PathState.Unknown;
            }
            var p = env.ExpandVariables(path.Trim().Trim('"').Trim());
            // Ab MAX_PATH (260) melden Windows-Funktionen ohne langen Pfad unter Umständen „Pfad nicht gefunden“, obwohl es
            // die Datei gibt: nie als fehlend werten.
            if (string.IsNullOrEmpty(p) || p.Length >= MaxPath || !Regex.IsMatch(p, @"^[A-Za-z]:\\"))
            {
                return PathState.Unknown;
            }
            var root = Path.GetPathRoot(p);
            if (string.IsNullOrEmpty(root) || !env.RootReachable(root)
                || !string.Equals(root, env.SystemDriveRoot, IgnoreCase) || env.DriveType(root) != "Fixed")
            {
                return PathState.Unknown;
            }
            if (env.IsUserProfilePath(p))
            {
                return PathState.Unknown;
            }
            if (string.Equals(architecture, "X86", IgnoreCase)
                && env.NativeProgramFolders.Any(f => !string.IsNullOrEmpty(f) && p.StartsWith(f.TrimEnd('\\') + "\\", IgnoreCase)))
            {
                return PathState.Unknown;
            }
            return env.PathStatus(p);
        }

        public static PathState GetPathState(string path, IOrphanEnvironment env) => GetPathState(path, null, env);

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
                var candidate = ResolveCommandPath(env.ExpandVariables(text.Substring(0, cut)), env);
                if (candidate is not null && env.FileExists(candidate))
                {
                    chosen = cut;
                    break;
                }
            }
            return ResolveCommandPath(env.ExpandVariables(text.Substring(0, chosen)), env);
        }

        /// <summary>Pfade ohne Wurzel werden an System32 gehängt, nie über PATH gesucht; null bleibt null (nicht auswertbar).</summary>
        public static string ResolveCommandPath(string path, IOrphanEnvironment env) =>
            path is null ? null : Path.IsPathRooted(path) ? path : Path.Combine(env.SystemFolder, path);

        public static string NullIfEmpty(string value)
        {
            if (value is null)
            {
                return null;
            }
            var text = value.Trim();
            return text.Length > 0 ? text : null;
        }

        /// <summary>
        /// "C:\Programme\App\app.exe",0 wird zu C:\Programme\App\app.exe. Variablen bleiben stehen und werden erst in
        /// <see cref="GetPathState(string, string, IOrphanEnvironment)"/> eingesetzt: Lässt sich eine nicht einsetzen, ist der
        /// Pfad dort Unknown (nicht „ohne Symbol“).
        /// </summary>
        public static string ConvertFromDisplayIcon(string value, IOrphanEnvironment env)
        {
            var text = NullIfEmpty(value);
            if (text is null)
            {
                return null;
            }
            return NullIfEmpty(Regex.Replace(text, @",\s*-?\d+$", "").Trim('"', ' '));
        }
    }
}
