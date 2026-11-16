#nullable disable
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace SoftwareInventory.Helper
{
    /// <summary>Was die Einzelprüfung einer Sicherungsdatei braucht; alles stammt aus demselben geöffneten Handle.</summary>
    public sealed class BackupFileInfo
    {
        /// <summary>Die Datei selbst ist ein Link (Symlink/Reparse-Point), geöffnet ohne ihm zu folgen.</summary>
        public bool IsReparsePoint { get; set; }

        /// <summary>Anzahl der Hardlinks auf die Datei; nur 1 ist in Ordnung.</summary>
        public int LinkCount { get; set; }

        /// <summary>Besitzer als SID-Zeichenfolge.</summary>
        public string OwnerSid { get; set; }

        /// <summary>SIDs mit Schreibrecht auf die Datei (siehe <see cref="WindowsDirectoryInspector.WriteSidsFromDescriptor"/>).</summary>
        public IReadOnlyList<string> WriteAccessSids { get; set; } = new string[0];
    }

    /// <summary>
    /// Einzelprüfung einer Sicherungsdatei im Admin-Ordner, bevor der Helfer sie importiert, und die Dekodierung ihrer
    /// Bytes (dieselben Regeln wie Get-RegistryBackupText im Modul, gemeinsame Tabelle
    /// tests/Data/registry-backup-cases.json). Die Datei wird genau einmal über ein Handle gelesen: Diese Bytes und diese
    /// Angaben werden geprüft und danach verwendet, der Pfad nicht erneut aufgelöst.
    /// </summary>
    public static class BackupFileRules
    {
        /// <summary>Größte erlaubte Sicherungsdatei (16 MB).</summary>
        public const long MaxBytes = 16L * 1024 * 1024;

        /// <summary>
        /// null, wenn die Datei in Ordnung ist. Sonst: BackupFileReparsePoint, BackupFileHardLinked, BackupFileBadOwner
        /// oder BackupFileWritable (Args: Pfad, bei Hardlinks die Anzahl, bei Besitzer/Schreibrecht die SID).
        /// </summary>
        public static Problem CheckFile(string path, BackupFileInfo info)
        {
            if (info.IsReparsePoint)
            {
                return new Problem("BackupFileReparsePoint", path);
            }
            if (info.LinkCount != 1)
            {
                return new Problem("BackupFileHardLinked", path, info.LinkCount);
            }
            if (!IsTrusted(info.OwnerSid))
            {
                return new Problem("BackupFileBadOwner", path, info.OwnerSid ?? "");
            }
            var writer = info.WriteAccessSids.FirstOrDefault(sid => !IsTrusted(sid));
            if (writer is not null)
            {
                return new Problem("BackupFileWritable", path, writer);
            }
            return null;
        }

        /// <summary>
        /// Prüft die Bytes und liest daraus den Text (UTF-16 Little Endian mit Bytefolge FF FE wie von reg export, gerade
        /// Anzahl Bytes danach). null, wenn alles passt; sonst der Grund-Code: Empty, TooLarge oder BadEncoding.
        /// </summary>
        public static string DecodeText(byte[] bytes, out string text)
        {
            text = null;
            if (bytes is null || bytes.Length == 0)
            {
                return "Empty";
            }
            if (bytes.Length > MaxBytes)
            {
                return "TooLarge";
            }
            if (bytes.Length < 2 || bytes[0] != 0xFF || bytes[1] != 0xFE || (bytes.Length - 2) % 2 != 0)
            {
                return "BadEncoding";
            }
            text = Encoding.Unicode.GetString(bytes, 2, bytes.Length - 2);
            return null;
        }

        private static bool IsTrusted(string sid) =>
            sid is not null && BackupFolderRules.TrustedSids.Any(t => string.Equals(t, sid, StringComparison.OrdinalIgnoreCase));
    }
}
