#nullable disable
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Text;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace SoftwareInventory.Helper
{
    /// <summary>
    /// Die echte Umsetzung von <see cref="IRegistryRemovalSystem"/> im erhöhten Helfer (nur .NET Framework: FileStream mit
    /// FileSecurity). Rechte als SDDL, damit sie beim Anlegen atomar gelten und nie nachträglich geändert werden.
    /// </summary>
    internal sealed class WindowsRegistryRemovalSystem : IRegistryRemovalSystem, IRegistryBackupSystem
    {
        // Die Rechte (SDDL) stehen in BackupFolderRules, damit die Tests sie ohne Adminrechte prüfen können.
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
            // Einen bestehenden Elternordner erst prüfen, dann darunter anlegen: sonst entstünde der Ordner bei einem Link am Ziel.
            var parentProblem = Directory.Exists(parent)
                ? BackupFolderRules.Check(parent, _paths.ProgramFiles, new WindowsDirectoryInspector())
                : CreateIfMissing(parent, BackupFolderRules.ParentSddl);
            return parentProblem ?? CreateIfMissing(BackupFolder, BackupFolderRules.FolderSddl);
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

        public Problem CheckBackupFolder()
        {
            var problem = BackupFolderRules.Check(BackupFolder, _paths.ProgramFiles, new WindowsDirectoryInspector());
            if (problem is not null)
            {
                return problem;
            }
            try
            {
                var bytes = new DirectoryInfo(BackupFolder).GetAccessControl(AccessControlSections.Access).GetSecurityDescriptorBinaryForm();
                return BackupFolderRules.LimitsOwnerRightsOfNewFiles(new RawSecurityDescriptor(bytes, 0))
                    ? null
                    : new Problem("BackupFolderOwnerRightsMissing", BackupFolder);
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException || ex is InvalidOperationException)
            {
                return new Problem("BackupFolderUnreadable", BackupFolder);
            }
        }

        /// <summary>reg.exe aus System32 mit festem Arbeitsordner und 64-Bit-Ansicht; Name und Pfad enthalten kein Anführungszeichen.</summary>
        public int ExportKey(string nativeKey, string file)
        {
            if (nativeKey.IndexOf('"') >= 0 || file.IndexOf('"') >= 0)
            {
                return -1;
            }
            return RunReg("export \"" + nativeKey + "\" \"" + file + "\" /y /reg:64");
        }

        /// <summary>reg.exe import genau dieser (vorher geprüften) Datei in der 64-Bit-Ansicht.</summary>
        public int ImportFile(string path)
        {
            if (path.IndexOf('"') >= 0)
            {
                return -1;
            }
            return RunReg("import \"" + path + "\" /reg:64");
        }

        public bool BackupFolderExists() => Directory.Exists(BackupFolder);

        public bool FileExists(string path) => File.Exists(path);

        /// <summary>Oberste Ebene des Ordners, ohne Links zu folgen (Attribute aus der Aufzählung selbst).</summary>
        public IReadOnlyList<BackupFolderEntry> ListFolder() =>
            new DirectoryInfo(BackupFolder).EnumerateFileSystemInfos("*", SearchOption.TopDirectoryOnly)
                .Select(info => new BackupFolderEntry
                {
                    Name = info.Name,
                    IsDirectory = (info.Attributes & FileAttributes.Directory) != 0,
                    IsReparsePoint = (info.Attributes & FileAttributes.ReparsePoint) != 0,
                    LastWriteUtc = info.LastWriteTimeUtc,
                })
                .ToList();

        /// <summary>Begleitdatei wie eine Sicherungsdatei lesen (ein Handle, Besitzer, Schreibrechte), höchstens 64 KB, UTF-8.</summary>
        public BackupSidecar ReadSidecar(string path, out Problem fileProblem)
        {
            var read = new WindowsBackupFileReader().Read(path);
            fileProblem = BackupFileRules.CheckFile(path, read.Info);
            if (fileProblem is not null)
            {
                return null;
            }
            if (read.Bytes is null || read.Bytes.Length == 0 || read.Bytes.Length > SidecarMaxBytes)
            {
                return null;
            }
            string json;
            try
            {
                json = new UTF8Encoding(false, true).GetString(read.Bytes);
            }
            catch (ArgumentException)
            {
                return null;
            }
            if (!(new JavaScriptSerializer().DeserializeObject(json) is Dictionary<string, object> data))
            {
                return null;
            }
            string Text(string name) => data.TryGetValue(name, out var value) ? value as string : null;
            return new BackupSidecar
            {
                SchemaVersion = data.TryGetValue("SchemaVersion", out var version) && version is int number ? number : 0,
                ActionId = Text("ActionId"),
                NativeKey = Text("NativeKey"),
                Scope = Text("Scope"),
            };
        }

        /// <summary>Größte erlaubte Begleitdatei (wie $script:RegistryBackupSidecarMaxBytes im Modul).</summary>
        private const int SidecarMaxBytes = 64 * 1024;

        private int RunReg(string arguments)
        {
            var info = new ProcessStartInfo(Path.Combine(_paths.System32, "reg.exe"), arguments)
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
                        try
                        {
                            process.Kill();
                            // Kurz warten, damit reg.exe die Zwischendatei freigibt und das Aufräumen sie löschen kann.
                            process.WaitForExit(5000);
                        }
                        catch (InvalidOperationException)
                        {
                            // Inzwischen von selbst beendet.
                        }
                        catch (Win32Exception)
                        {
                            // Lässt sich nicht beenden; das Ergebnis bleibt „gescheitert“.
                        }
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
            security.SetSecurityDescriptorSddlForm(BackupFolderRules.FileSddl);
            var created = false;
            try
            {
                using (var stream = new FileStream(path, FileMode.CreateNew, FileSystemRights.Write, FileShare.None, 4096, FileOptions.WriteThrough, security))
                {
                    created = true;
                    stream.Write(bytes, 0, bytes.Length);
                }
            }
            catch
            {
                // Eine selbst angelegte, unvollständige Datei (z. B. Datenträger voll) nicht liegen lassen; eine fremde nie anfassen.
                if (created)
                {
                    DeleteFile(path);
                }
                throw;
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
