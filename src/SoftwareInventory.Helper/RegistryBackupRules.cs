#nullable disable
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace SoftwareInventory.Helper
{
    /// <summary>Ein Uninstall-Zweig der Registry als nativer Pfad (HKEY_LOCAL_MACHINE\...) und sein Bereich (User oder Machine).</summary>
    public sealed class UninstallLocation
    {
        public UninstallLocation(string nativePath, string scope)
        {
            NativePath = nativePath;
            Scope = scope;
        }

        public string NativePath { get; }

        public string Scope { get; }
    }

    /// <summary>
    /// Strenge Prüfung einer .reg-Sicherung, bevor der Helfer sie importiert. Dieselben Regeln wie das Modul
    /// (Test-RegistryBackupContent); beide prüfen gegen tests/Data/registry-backup-cases.json.
    /// Erlaubt ist genau ein Hauptschlüssel (der aus der Begleitdatei) direkt unter einem Uninstall-Zweig des
    /// erlaubten Bereichs; jeder weitere Schlüsselkopf muss mit "&lt;Hauptschlüssel&gt;\" beginnen. Keine
    /// Löschzeilen, nur CRLF als Zeilenumbruch.
    /// </summary>
    public static class RegistryBackupRules
    {
        public const string Header = "Windows Registry Editor Version 5.00";

        // reg export schreibt nur CRLF. Einzelne CR/LF, NUL oder andere Zeilentrenner lehnen wir ab: Würde reg.exe
        // dort anders trennen als diese Prüfung, könnte sich eine Schlüsselzeile an der Prüfung vorbeischmuggeln.
        private static readonly Regex OddLineBreaks = new Regex("[\\x00\\x0B\\x0C\\u0085\\u2028\\u2029]|\\r(?!\\n)|(?<!\\r)\\n", RegexOptions.Compiled);
        private static readonly Regex KeyLine = new Regex(@"^\[(?<key>[^\]]+)\]$", RegexOptions.Compiled);
        // Fortsetzungszeile eines Hex-Werts (reg export: "  01,02,\").
        private static readonly Regex HexLine = new Regex(@"^[0-9A-Fa-f]{2}(,[0-9A-Fa-f]{2})*,?\\?$", RegexOptions.Compiled);
        private static readonly char[] Blanks = { ' ', '\t' };

        /// <summary>
        /// null, wenn der Inhalt passt; sonst der Grund: Empty, BadLineBreak, BadHeader, BadLine, DeleteLine, BadKeyLine,
        /// KeyNotFound, KeyMismatch, KeyOutside, KeyNotUninstall, MachineNotYet (HKLM, aber nur Benutzer erlaubt)
        /// oder WrongScope (HKCU, aber nur HKLM erlaubt).
        /// </summary>
        public static string CheckContent(string text, string nativeKey, string allowedScope, IEnumerable<UninstallLocation> locations)
        {
            if (string.IsNullOrEmpty(text) || string.IsNullOrEmpty(nativeKey))
            {
                return "Empty";
            }
            if (OddLineBreaks.IsMatch(text))
            {
                return "BadLineBreak";
            }
            var lines = text.Split(new[] { "\r\n" }, StringSplitOptions.None);
            if (!string.Equals(lines[0].TrimEnd(Blanks), Header, StringComparison.Ordinal))
            {
                return "BadHeader";
            }

            var headers = new List<string>();
            foreach (var line in lines.Skip(1))
            {
                // Nur Leerzeichen und Tabulator werden abgeschnitten (nicht von der Laufzeit abhängig): Eine Zeile mit
                // einem anderen führenden Zeichen, auch unsichtbaren wie U+00AD oder U+200B, ist kein bekanntes Format.
                var trimmed = line.Trim(Blanks);
                if (trimmed.Length == 0)
                {
                    continue;
                }
                if (!trimmed.StartsWith("[", StringComparison.Ordinal))
                {
                    // Wertzeilen ("Name"=..., @=...), Kommentare und Hex-Fortsetzungen; alles andere ist unbekannt.
                    if (trimmed[0] == '"' || trimmed[0] == '@' || trimmed[0] == ';' || HexLine.IsMatch(trimmed))
                    {
                        continue;
                    }
                    return "BadLine";
                }
                if (trimmed.StartsWith("[-", StringComparison.Ordinal))
                {
                    return "DeleteLine";
                }
                var match = KeyLine.Match(trimmed);
                if (!match.Success)
                {
                    return "BadKeyLine";
                }
                headers.Add(match.Groups["key"].Value);
            }
            if (headers.Count == 0)
            {
                return "KeyNotFound";
            }
            if (!string.Equals(headers[0], nativeKey, StringComparison.OrdinalIgnoreCase))
            {
                return "KeyMismatch";
            }
            // Ein Hauptschlüssel mit \ am Ende oder leerer Komponente (\\) wäre der Zweig selbst: Der Präfix ließe dann
            // jeden Schlüssel darunter zu.
            if (nativeKey.EndsWith("\\", StringComparison.Ordinal) || nativeKey.Contains("\\\\"))
            {
                return "KeyNotUninstall";
            }
            var prefix = nativeKey + "\\";
            if (headers.Skip(1).Any(h => !h.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) || h.EndsWith("\\", StringComparison.Ordinal) || h.Contains("\\\\")))
            {
                return "KeyOutside";
            }

            var cut = nativeKey.LastIndexOf('\\');
            if (cut < 1)
            {
                return "KeyNotUninstall";
            }
            var parent = nativeKey.Substring(0, cut);
            var location = locations.FirstOrDefault(l => string.Equals(l.NativePath, parent, StringComparison.OrdinalIgnoreCase));
            if (location is null)
            {
                return "KeyNotUninstall";
            }
            if (!string.Equals(location.Scope, allowedScope, StringComparison.Ordinal))
            {
                return location.Scope == "Machine" ? "MachineNotYet" : "WrongScope";
            }
            return null;
        }
    }
}
