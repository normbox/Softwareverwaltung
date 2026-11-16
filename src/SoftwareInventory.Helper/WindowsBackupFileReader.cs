#nullable disable
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;

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
            public FILETIME CreationTime;
            public FILETIME LastAccessTime;
            public FILETIME LastWriteTime;
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

        /// <summary>
        /// Liest die Datei. Wirft FileNotFoundException, UnauthorizedAccessException oder IOException, wenn sie sich nicht
        /// öffnen lässt: Der Aufrufer behandelt das als „nicht lesbar“ und lehnt ab.
        /// </summary>
        public BackupFileRead Read(string path)
        {
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
