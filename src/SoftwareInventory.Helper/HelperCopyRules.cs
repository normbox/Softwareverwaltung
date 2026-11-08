#nullable disable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace SoftwareInventory.Helper
{
    /// <summary>
    /// Regeln für die geschützte Kopie unter Program Files\Softwareverwaltung\Helper\&lt;Version&gt;.
    /// Der Plan kommt aus einem Prozess ohne Adminrechte, deshalb wird ihm nichts geglaubt.
    /// </summary>
    public static class HelperCopyRules
    {
        public const string FileName = "SoftwareInventory.Helper.exe";

        public static bool IsVersionName(string name) => name != null && Regex.IsMatch(name, @"^\d+(\.\d+){1,3}$");

        /// <summary>Der Helfer-Ordner, wenn die Exe genau in der geschützten Struktur liegt; sonst null.</summary>
        public static string CopyRoot(string exePath, string programFiles)
        {
            var root = Path.Combine(programFiles, "Softwareverwaltung", "Helper");
            var directory = Path.GetDirectoryName(exePath);
            if (!string.Equals(Path.GetFileName(exePath), FileName, StringComparison.OrdinalIgnoreCase)
                || !string.Equals(Path.GetDirectoryName(directory), root, StringComparison.OrdinalIgnoreCase)
                || !IsVersionName(Path.GetFileName(directory)))
            {
                return null;
            }
            return root;
        }

        /// <summary>Nur Versionsordner, die älter sind als der eigene; eine neuere Version bleibt liegen.</summary>
        public static IEnumerable<string> OlderSiblings(string ownVersion, IEnumerable<string> directories)
        {
            var own = new Version(ownVersion);
            return directories.Where(d =>
            {
                var name = Path.GetFileName(d);
                return IsVersionName(name) && new Version(name) < own;
            }).ToList();
        }

        /// <summary>Austausch nur von der geschützten Exe aus und nur bei gültiger Signatur desselben Herausgebers.</summary>
        public static Problem CheckReplace(string exePath, string programFiles, string sourcePath, string targetVersion, string ownPublisher, string sourcePublisher)
        {
            if (CopyRoot(exePath, programFiles) == null)
            {
                return new Problem("HelperCopyNotProtected");
            }
            if (!IsVersionName(targetVersion))
            {
                return new Problem("HelperCopyInvalidVersion", targetVersion ?? "");
            }
            if (!string.Equals(Path.GetFileName(sourcePath ?? ""), FileName, StringComparison.OrdinalIgnoreCase))
            {
                return new Problem("HelperCopyUntrusted");
            }
            if (string.IsNullOrEmpty(ownPublisher) || string.IsNullOrEmpty(sourcePublisher))
            {
                return new Problem("HelperCopyUntrusted");
            }
            if (!string.Equals(ownPublisher, sourcePublisher, StringComparison.Ordinal))
            {
                return new Problem("HelperCopyPublisherMismatch");
            }
            return null;
        }
    }
}
