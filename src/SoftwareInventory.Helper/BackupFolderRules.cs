#nullable disable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace SoftwareInventory.Helper
{
    /// <summary>
    /// Was die Ordnerprüfung vom Dateisystem wissen muss. Ein Adapter, damit sich die Regeln ohne echte
    /// Administrator-ACLs testen lassen (WindowsDirectoryInspector ist die echte Umsetzung).
    /// </summary>
    public interface IDirectoryInspector
    {
        bool Exists(string path);

        /// <summary>Symbolischer Link oder Junction (Reparse-Point).</summary>
        bool IsReparsePoint(string path);

        /// <summary>Besitzer als SID-Zeichenfolge.</summary>
        string OwnerSid(string path);

        /// <summary>
        /// SIDs, die für den Ordner selbst ein Schreib-Recht erlaubt bekommen (Daten oder Anhängen schreiben,
        /// Attribute schreiben, Löschen, Berechtigungen ändern, Besitz übernehmen). Nur Erlauben-Einträge, die für
        /// den Ordner selbst gelten (nicht „nur Unterobjekte“).
        /// </summary>
        IReadOnlyList<string> WriteAccessSids(string path);
    }

    /// <summary>
    /// Der Ordner für HKLM-Sicherungen (Program Files\Softwareverwaltung\RegistryBackup) darf nur von Administratoren
    /// beschrieben werden. Ein Programm ohne Adminrechte kann unter Program Files nichts anlegen; geprüft wird trotzdem
    /// bei jeder Nutzung, für jede Pfadkomponente: kein Reparse-Point, Besitzer Administratoren/SYSTEM/TrustedInstaller,
    /// kein Schreib-Recht für andere. Schlägt eine Prüfung fehl, lehnt der Helfer ab und repariert nichts: Was schon im
    /// Ordner liegt, wäre nicht mehr vertrauenswürdig.
    /// </summary>
    public static class BackupFolderRules
    {
        public const string SystemSid = "S-1-5-18";
        public const string AdministratorsSid = "S-1-5-32-544";
        public const string TrustedInstallerSid = "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464";

        public static readonly string[] TrustedSids = { SystemSid, AdministratorsSid, TrustedInstallerSid };

        /// <summary>Der feste Ort: nur unter Program Files, nie unter einem Pfad, den der Plan nennt.</summary>
        public static string FolderPath(HelperPaths paths) => Path.Combine(paths.ProgramFiles, "Softwareverwaltung", "RegistryBackup");

        /// <summary>
        /// null, wenn der Ordner und jede Komponente darüber (unterhalb von Program Files) die Regeln erfüllen. Sonst:
        /// BackupFolderOutsideRoot, BackupFolderMissing, BackupFolderReparsePoint, BackupFolderBadOwner oder
        /// BackupFolderWritable (Args: Pfad, bei Besitzer/Schreibrecht die SID).
        /// </summary>
        public static Problem Check(string folder, string programFiles, IDirectoryInspector fs)
        {
            if (string.IsNullOrEmpty(folder) || string.IsNullOrEmpty(programFiles))
            {
                return new Problem("BackupFolderOutsideRoot", folder ?? "");
            }
            var full = Path.GetFullPath(folder).TrimEnd('\\');
            var root = Path.GetFullPath(programFiles).TrimEnd('\\');
            if (!full.StartsWith(root + "\\", StringComparison.OrdinalIgnoreCase))
            {
                return new Problem("BackupFolderOutsideRoot", full);
            }

            var current = root;
            foreach (var part in full.Substring(root.Length + 1).Split('\\'))
            {
                current += "\\" + part;
                if (!fs.Exists(current))
                {
                    return new Problem("BackupFolderMissing", current);
                }
                if (fs.IsReparsePoint(current))
                {
                    return new Problem("BackupFolderReparsePoint", current);
                }
                var owner = fs.OwnerSid(current);
                if (!IsTrusted(owner))
                {
                    return new Problem("BackupFolderBadOwner", current, owner ?? "");
                }
                var writer = fs.WriteAccessSids(current).FirstOrDefault(sid => !IsTrusted(sid));
                if (writer is not null)
                {
                    return new Problem("BackupFolderWritable", current, writer);
                }
            }
            return null;
        }

        private static bool IsTrusted(string sid) =>
            sid is not null && TrustedSids.Any(t => string.Equals(t, sid, StringComparison.OrdinalIgnoreCase));
    }
}
