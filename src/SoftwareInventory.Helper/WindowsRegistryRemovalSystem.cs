#nullable disable
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using Microsoft.Win32;

namespace SoftwareInventory.Helper
{
    /// <summary>
    /// Die echte Umsetzung von <see cref="IRegistryRemovalSystem"/> im erhöhten Helfer (nur .NET Framework: FileStream mit
    /// FileSecurity). Rechte als SDDL, damit sie beim Anlegen atomar gelten und nie nachträglich geändert werden.
    /// </summary>
    internal sealed class WindowsRegistryRemovalSystem : IRegistryRemovalSystem
    {
        /// <summary>
        /// Program Files\Softwareverwaltung, nur wenn er fehlt: Besitzer Administratoren, die Rechte erbt er unverändert von
        /// Program Files (keine eigenen Einträge, auch keine zusätzlichen für Benutzer).
        /// </summary>
        internal const string ParentSddl = "O:BAG:SY";

        /// <summary>
        /// RegistryBackup und alles darin: Besitzer Administratoren, geschützte DACL. SYSTEM und Administratoren Vollzugriff,
        /// Benutzer nur Lesen und Ausführen (0x1200a9). OWNER RIGHTS ebenfalls nur Lesen und Ausführen: Eine Datei, die
        /// reg.exe unter dem Standardbesitzer des Tokens anlegt (je nach Richtlinie der Benutzer), lässt sich dann von diesem
        /// Besitzer nicht über die Rechte ändern.
        /// </summary>
        internal const string FolderSddl = "O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)(A;OICI;0x1200a9;;;OW)";

        /// <summary>Eine Sicherungsdatei, die der Helfer selbst schreibt: wie der Ordner, ohne Vererbung nach unten.</summary>
        internal const string FileSddl = "O:BAG:SYD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x1200a9;;;BU)";

        private const int ErrorAlreadyExists = 183;
        private const int ExportTimeoutMilliseconds = 60000;

        [StructLayout(LayoutKind.Sequential)]
        private struct SecurityAttributes
        {
            public int Length;
            public IntPtr SecurityDescriptor;
            public bool InheritHandle;
        }

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string sddl, uint revision, out IntPtr descriptor, IntPtr size);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CreateDirectoryW(string path, ref SecurityAttributes attributes);

        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr memory);

        private readonly HelperPaths _paths;

        public WindowsRegistryRemovalSystem(HelperPaths paths, bool elevated)
        {
            _paths = paths;
            Elevated = elevated;
            BackupFolder = BackupFolderRules.FolderPath(paths);
        }

        public bool Elevated { get; }

        public IOrphanEnvironment Environment { get; } = new WindowsOrphanEnvironment();

        public string BackupFolder { get; }

        public DateTime UtcNow => DateTime.UtcNow;

        private static RegistryKey MachineRoot() => RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);

        private static string SubKey(string nativeKey) => nativeKey.Substring(@"HKEY_LOCAL_MACHINE\".Length);

        public UninstallEntry ReadEntry(string nativeKey)
        {
            using (var root = MachineRoot())
            using (var key = root.OpenSubKey(SubKey(nativeKey), false))
            {
                if (key is null)
                {
                    return null;
                }
                // Rohe Werte: REG_EXPAND_SZ nicht über die Umgebung des Prozesses einsetzen (die kommt auch aus HKCU).
                string Raw(string name) => key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
                var installer = key.GetValue("WindowsInstaller", null, RegistryValueOptions.DoNotExpandEnvironmentNames);
                return new UninstallEntry
                {
                    DisplayName = Raw("DisplayName"),
                    IsMsi = installer is int number ? number == 1 : string.Equals(Convert.ToString(installer), "1", StringComparison.Ordinal),
                    UninstallString = Raw("UninstallString"),
                    QuietUninstallString = Raw("QuietUninstallString"),
                    InstallLocation = Raw("InstallLocation"),
                    DisplayIcon = Raw("DisplayIcon"),
                };
            }
        }

        public Problem CreateBackupFolderIfMissing()
        {
            var parent = Path.GetDirectoryName(BackupFolder);
            return CreateIfMissing(parent, ParentSddl) ?? CreateIfMissing(BackupFolder, FolderSddl);
        }

        /// <summary>Legt den Ordner mit genau diesen Rechten an; gibt es ihn schon, bleibt er, wie er ist (geprüft wird danach).</summary>
        private static Problem CreateIfMissing(string path, string sddl)
        {
            if (Directory.Exists(path))
            {
                return null;
            }
            if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, 1, out var descriptor, IntPtr.Zero))
            {
                return new Problem("BackupFolderCreateFailed", path, Marshal.GetLastWin32Error());
            }
            try
            {
                var attributes = new SecurityAttributes { Length = Marshal.SizeOf<SecurityAttributes>(), SecurityDescriptor = descriptor };
                if (!CreateDirectoryW(path, ref attributes))
                {
                    var error = Marshal.GetLastWin32Error();
                    return error == ErrorAlreadyExists ? null : new Problem("BackupFolderCreateFailed", path, error);
                }
                return null;
            }
            finally
            {
                LocalFree(descriptor);
            }
        }

        public Problem CheckBackupFolder() => BackupFolderRules.Check(BackupFolder, _paths.ProgramFiles, new WindowsDirectoryInspector());

        /// <summary>reg.exe aus System32 mit festem Arbeitsordner und 64-Bit-Ansicht; Name und Pfad enthalten kein Anführungszeichen.</summary>
        public int ExportKey(string nativeKey, string file)
        {
            if (nativeKey.IndexOf('"') >= 0 || file.IndexOf('"') >= 0)
            {
                return -1;
            }
            var info = new ProcessStartInfo(Path.Combine(_paths.System32, "reg.exe"), "export \"" + nativeKey + "\" \"" + file + "\" /y /reg:64")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = _paths.System32,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            try
            {
                using (var process = Process.Start(info))
                {
                    // Ausgabe nur leeren, damit reg.exe nicht an einer vollen Pipe hängt; ausgewertet wird der Exit-Code.
                    _ = process.StandardOutput.ReadToEndAsync();
                    _ = process.StandardError.ReadToEndAsync();
                    if (!process.WaitForExit(ExportTimeoutMilliseconds))
                    {
                        process.Kill();
                        return -1;
                    }
                    process.WaitForExit();
                    return process.ExitCode;
                }
            }
            catch (Win32Exception)
            {
                return -1;
            }
        }

        public BackupFileRead ReadFile(string path) => new WindowsBackupFileReader().Read(path);

        public void WriteNewFile(string path, byte[] bytes)
        {
            var security = new FileSecurity();
            security.SetSecurityDescriptorSddlForm(FileSddl);
            using (var stream = new FileStream(path, FileMode.CreateNew, FileSystemRights.Write, FileShare.None, 4096, FileOptions.WriteThrough, security))
            {
                stream.Write(bytes, 0, bytes.Length);
            }
        }

        public void DeleteFile(string path)
        {
            try
            {
                File.Delete(path);
            }
            catch (IOException)
            {
                // Aufräumen ist eine Zugabe; ein Rest im Admin-Ordner schadet nicht.
            }
            catch (UnauthorizedAccessException)
            {
                // Ebenso.
            }
        }

        public void DeleteKey(string nativeKey)
        {
            using (var root = MachineRoot())
            {
                root.DeleteSubKeyTree(SubKey(nativeKey), false);
            }
        }

        public bool KeyExists(string nativeKey)
        {
            using (var root = MachineRoot())
            using (var key = root.OpenSubKey(SubKey(nativeKey), false))
            {
                return key is not null;
            }
        }
    }
}
