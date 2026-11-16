#nullable disable
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;
using FileTime = System.Runtime.InteropServices.ComTypes.FILETIME;

namespace SoftwareInventory.Helper
{
    /// <summary>Ergebnis von <see cref="WindowsBackupFileReader.Read"/>: die Angaben und, wenn lesbar, die Bytes aus demselben Handle.</summary>
    public sealed class BackupFileRead
    {
        public BackupFileInfo Info { get; set; }

        /// <summary>Dateigröße laut Handle.</summary>
        public long Size { get; set; }

        /// <summary>Die Bytes; null, wenn die Datei ein Link ist oder größer als <see cref="BackupFileRules.MaxBytes"/>.</summary>
        public byte[] Bytes { get; set; }
    }

    /// <summary>
    /// Öffnet eine Sicherungsdatei genau einmal, ohne einem Link zu folgen (FILE_FLAG_OPEN_REPARSE_POINT), mit
    /// FILE_SHARE_READ (niemand kann währenddessen schreiben), und liest daraus Attribute, Hardlink-Anzahl, Besitzer,
    /// Zugriffsrechte und die Bytes. Alles über dasselbe Handle: Zwischen Prüfung und Nutzung gibt es keine Pfadauflösung.
    /// </summary>
    public sealed class WindowsBackupFileReader
    {
        private const uint GenericRead = 0x80000000;
        private const uint FileShareRead = 0x00000001;
        private const uint OpenExisting = 3;
        private const uint FileFlagOpenReparsePoint = 0x00200000;
        private const uint FileAttributeReparsePoint = 0x400;

        [StructLayout(LayoutKind.Sequential)]
        private struct ByHandleFileInformation
        {
            public uint FileAttributes;
            public FileTime CreationTime;
            public FileTime LastAccessTime;
            public FileTime LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle file, out ByHandleFileInformation information);

        [DllImport("kernel32.dll")]
        private static extern uint GetFileType(SafeFileHandle file);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandleW(SafeFileHandle file, StringBuilder buffer, uint bufferLength, uint flags);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetLongPathNameW(string shortPath, StringBuilder longPath, uint length);

        private const uint FileTypeDisk = 1;
        private const uint FinalPathBufferLength = 2048;

        /// <summary>
        /// Nur ein einfacher Pfad der Form X:\... ist erlaubt: kein \\?\ oder \\.\ (Geräte), kein Doppelpunkt hinter dem
        /// Laufwerk (alternative Datenströme wie datei.reg:strom) und keine Platzhalter.
        /// </summary>
        public static bool IsPlainDrivePath(string path)
        {
            return path != null && path.Length >= 4 && char.IsLetter(path[0]) && path[0] < 128 && path[1] == ':' && path[2] == '\\'
                && path.IndexOf(':', 2) < 0 && path.IndexOfAny(new[] { '?', '*', '\0' }) < 0;
        }

        /// <summary>
        /// Stimmt das geöffnete Ziel mit dem angegebenen Pfad überein? Ein 8.3-Kurzname, ein Ordner-Link (Junction), ein
        /// Datenstrom oder ein abgeschnittener Name (Punkt, Leerzeichen am Ende) ergeben einen anderen aufgelösten Pfad.
        /// </summary>
        private static bool TargetMatches(SafeFileHandle handle, string path)
        {
            // Path.GetFullPath löst Kurznamen selbst auf und würde sie nicht auffallen lassen: Der angegebene Pfad muss
            // schon in der langen Schreibweise vorliegen (GetLongPathName ändert ihn nicht, abgesehen von der Groß-/Kleinschreibung).
            var longForm = new StringBuilder((int)FinalPathBufferLength);
            var longLength = GetLongPathNameW(path, longForm, FinalPathBufferLength);
            if (longLength == 0 || longLength >= FinalPathBufferLength || !string.Equals(longForm.ToString(), path, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
            var buffer = new StringBuilder((int)FinalPathBufferLength);
            var length = GetFinalPathNameByHandleW(handle, buffer, FinalPathBufferLength, 0);
            if (length == 0 || length >= FinalPathBufferLength)
            {
                return false;
            }
            var final = buffer.ToString();
            if (final.StartsWith(@"\\?\", StringComparison.Ordinal) && !final.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase))
            {
                final = final.Substring(4);
            }
            return string.Equals(final, Path.GetFullPath(path), StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// Liest die Datei. Wirft FileNotFoundException, UnauthorizedAccessException oder IOException, wenn sie sich nicht
        /// öffnen lässt: Der Aufrufer behandelt das als „nicht lesbar“ und lehnt ab.
        /// </summary>
        public BackupFileRead Read(string path)
        {
            // Ohne Text: Der Aufrufer bildet jede Ausnahme auf BackupFileUnreadable ab.
            if (!IsPlainDrivePath(path))
            {
                throw new IOException();
            }
            var handle = CreateFileW(path, GenericRead, FileShareRead, IntPtr.Zero, OpenExisting, FileFlagOpenReparsePoint, IntPtr.Zero);
            if (handle.IsInvalid)
            {
                var error = Marshal.GetLastWin32Error();
                handle.Dispose();
                if (error == 2 || error == 3)
                {
                    throw new FileNotFoundException("Die Sicherungsdatei fehlt.", path);
                }
                if (error == 5)
                {
                    throw new UnauthorizedAccessException(path);
                }
                throw new IOException("Die Sicherungsdatei lässt sich nicht öffnen (Fehler " + error + ").", error);
            }

            FileStream stream = null;
            try
            {
                if (!GetFileInformationByHandle(handle, out var raw))
                {
                    throw new IOException("Die Dateiangaben lassen sich nicht lesen.", Marshal.GetLastWin32Error());
                }
                if (GetFileType(handle) != FileTypeDisk)
                {
                    throw new IOException();
                }
                var info = new BackupFileInfo
                {
                    IsReparsePoint = (raw.FileAttributes & FileAttributeReparsePoint) != 0,
                    LinkCount = (int)raw.NumberOfLinks,
                };
                var result = new BackupFileRead { Info = info, Size = ((long)raw.FileSizeHigh << 32) | raw.FileSizeLow };
                if (info.IsReparsePoint)
                {
                    return result;
                }
                if (!TargetMatches(handle, path))
                {
                    throw new IOException();
                }

                stream = new FileStream(handle, FileAccess.Read, 4096, false);
                var security = stream.GetAccessControl();
                info.OwnerSid = security.GetOwner(typeof(SecurityIdentifier))?.Value;
                info.WriteAccessSids = WindowsDirectoryInspector.WriteSidsFromDescriptor(new RawSecurityDescriptor(security.GetSecurityDescriptorBinaryForm(), 0));
                if (result.Size <= BackupFileRules.MaxBytes)
                {
                    var bytes = new byte[result.Size];
                    var read = 0;
                    while (read < bytes.Length)
                    {
                        var n = stream.Read(bytes, read, bytes.Length - read);
                        if (n == 0)
                        {
                            break;
                        }
                        read += n;
                    }
                    if (read != bytes.Length)
                    {
                        throw new IOException("Die Sicherungsdatei wurde nicht vollständig gelesen.");
                    }
                    result.Bytes = bytes;
                }
                return result;
            }
            finally
            {
                if (stream is not null)
                {
                    stream.Dispose();
                }
                else
                {
                    handle.Dispose();
                }
            }
        }
    }
}
