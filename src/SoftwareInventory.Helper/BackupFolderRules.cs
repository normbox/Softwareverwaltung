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

    /// <summary>Welche Zugriffsrechte als „Schreiben“ zählen, und der Platzhalter für nicht auswertbare Einträge.</summary>
    public static class AclRules
    {
        /// <summary>Erlauben-Eintrag, den die Prüfung nicht einfach auswerten kann (Objekt, Callback, Compound): zählt als Schreibrecht.</summary>
        public const string UnsupportedAce = "unsupported-ace";

        // FILE_WRITE_DATA/ADD_FILE 0x2, FILE_APPEND_DATA/ADD_SUBDIRECTORY 0x4, FILE_WRITE_EA 0x10, FILE_DELETE_CHILD 0x40,
        // FILE_WRITE_ATTRIBUTES 0x100, DELETE 0x10000, WRITE_DAC 0x40000, WRITE_OWNER 0x80000 und die ungemappten
        // Sammelrechte GENERIC_ALL 0x10000000, GENERIC_WRITE 0x40000000, MAXIMUM_ALLOWED 0x02000000.
        private const uint WriteMask = 0x2 | 0x4 | 0x10 | 0x40 | 0x100 | 0x10000 | 0x40000 | 0x80000 | 0x10000000 | 0x40000000 | 0x02000000;

        public static bool IsWriteMask(uint mask) => (mask & WriteMask) != 0;
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

        public const string OwnerRightsSid = "S-1-3-4";

        public static readonly string[] TrustedSids = { SystemSid, AdministratorsSid, TrustedInstallerSid };

        /// <summary>
        /// Program Files\Softwareverwaltung, nur wenn er fehlt: Besitzer Administratoren, keine eigene DACL; die Rechte erbt er
        /// unverändert von Program Files (auch keine zusätzlichen für Benutzer).
        /// </summary>
        public const string ParentSddl = "O:BAG:SY";

        /// <summary>
        /// RegistryBackup und alles darin: Besitzer Administratoren, geschützte DACL. SYSTEM und Administratoren Vollzugriff,
        /// Benutzer nur Lesen und Ausführen (0x1200a9). OWNER RIGHTS ebenfalls nur Lesen und Ausführen: Eine Datei, die
        /// reg.exe unter dem Standardbesitzer des Tokens anlegt (je nach Richtlinie der Benutzer), erbt diesen Eintrag beim
        /// Anlegen, und ihr Besitzer kann ihre Rechte nicht ändern (kein implizites WRITE_DAC).
        /// </summary>
        public const string FolderSddl = "O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)(A;OICI;0x1200a9;;;OW)";

        /// <summary>Eine Sicherungsdatei, die der Helfer selbst schreibt: wie der Ordner, ohne Vererbung nach unten.</summary>
        public const string FileSddl = "O:BAG:SYD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x1200a9;;;BU)";

        /// <summary>
        /// Gibt der Ordner neuen Dateien einen OWNER-RIGHTS-Eintrag mit (Erlauben, vererbt an Dateien)? Nur dann hat der
        /// Besitzer einer Datei, die reg.exe dort anlegt, von Anfang an kein implizites Recht, ihre DACL zu ändern. Ohne den
        /// Eintrag lehnt der Helfer einen bestehenden Ordner ab (BackupFolderOwnerRightsMissing), ändert ihn aber nicht.
        /// Ob der Eintrag selbst Schreibrecht gibt, prüft die Datei (BackupFileRules.CheckStagedFile).
        /// </summary>
        public static bool LimitsOwnerRightsOfNewFiles(System.Security.AccessControl.RawSecurityDescriptor descriptor)
        {
            var acl = descriptor.DiscretionaryAcl;
            if (acl is null)
            {
                return false;
            }
            foreach (System.Security.AccessControl.GenericAce ace in acl)
            {
                if (ace is System.Security.AccessControl.CommonAce common
                    && ace.AceType == System.Security.AccessControl.AceType.AccessAllowed
                    && (ace.AceFlags & System.Security.AccessControl.AceFlags.ObjectInherit) != 0
                    && string.Equals(common.SecurityIdentifier.Value, OwnerRightsSid, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
            return false;
        }

        /// <summary>Der feste Ort: nur unter Program Files, nie unter einem Pfad, den der Plan nennt.</summary>
        public static string FolderPath(HelperPaths paths) => Path.Combine(paths.ProgramFiles, "Softwareverwaltung", "RegistryBackup");

        /// <summary>
        /// null, wenn der Ordner und jede Komponente darüber (unterhalb von Program Files) die Regeln erfüllen. Sonst:
        /// BackupFolderOutsideRoot, BackupFolderMissing, BackupFolderReparsePoint, BackupFolderBadOwner oder
        /// BackupFolderWritable (Args: Pfad, bei Besitzer/Schreibrecht die SID) oder BackupFolderUnreadable (Rechte nicht lesbar:
        /// fail-closed).
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
                try
                {
                    var problem = CheckComponent(current, fs);
                    if (problem is not null)
                    {
                        return problem;
                    }
                }
                catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException || ex is InvalidOperationException || ex is System.Security.SecurityException || ex is ArgumentException)
                {
                    return new Problem("BackupFolderUnreadable", current);
                }
            }
            return null;
        }

        private static Problem CheckComponent(string current, IDirectoryInspector fs)
        {
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
            return null;
        }

        private static bool IsTrusted(string sid) =>
            sid is not null && TrustedSids.Any(t => string.Equals(t, sid, StringComparison.OrdinalIgnoreCase));
    }
}
