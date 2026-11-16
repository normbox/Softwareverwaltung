#nullable disable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

namespace SoftwareInventory.Helper
{
    /// <summary>Die echte Umsetzung von <see cref="IOrphanEnvironment"/> über das Windows-Dateisystem.</summary>
    public sealed class WindowsOrphanEnvironment : IOrphanEnvironment
    {
        public string ExpandVariables(string text) => Environment.ExpandEnvironmentVariables(text);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFileAttributesW(string fileName);

        private const uint InvalidFileAttributes = 0xFFFFFFFF;
        private const int ErrorFileNotFound = 2;
        private const int ErrorPathNotFound = 3;

        /// <summary>Nur „Datei oder Pfad nicht gefunden“ ist Missing; Zugriff verweigert und alles andere ist Unknown.</summary>
        public PathState PathStatus(string path)
        {
            if (GetFileAttributesW(path) != InvalidFileAttributes)
            {
                return PathState.Exists;
            }
            var error = Marshal.GetLastWin32Error();
            return error == ErrorFileNotFound || error == ErrorPathNotFound ? PathState.Missing : PathState.Unknown;
        }

        public string SystemDriveRoot => Path.GetPathRoot(Environment.SystemDirectory);

        public IReadOnlyList<string> NativeProgramFolders => new[]
        {
            Environment.GetEnvironmentVariable("ProgramW6432"),
            Environment.GetEnvironmentVariable("CommonProgramW6432"),
        }.Where(folder => !string.IsNullOrEmpty(folder)).ToList();

        public bool FileExists(string path) => File.Exists(path);

        public bool RootReachable(string root) => Directory.Exists(root);

        public string DriveType(string root)
        {
            try
            {
                return new DriveInfo(root).DriveType.ToString();
            }
            catch (ArgumentException)
            {
                return null;
            }
        }

        /// <summary>
        /// Pfade unter SystemDrive\Users: Bei einer UAC-Abfrage mit fremdem Administratorkonto zeigen %USERPROFILE% und
        /// %LOCALAPPDATA% auf das Profil des Administrators, nicht des Benutzers. Solche Pfade lassen sich im erhöhten
        /// Helfer nicht sicher beurteilen.
        /// </summary>
        public bool IsUserProfilePath(string path)
        {
            var systemDrive = Path.GetPathRoot(Environment.SystemDirectory);
            var users = Path.Combine(systemDrive, "Users").TrimEnd('\\') + "\\";
            return path.StartsWith(users, StringComparison.OrdinalIgnoreCase);
        }

        public IReadOnlyList<string> SystemFolders => new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            Environment.GetFolderPath(Environment.SpecialFolder.SystemX86),
            Environment.GetEnvironmentVariable("WINDIR"),
        }.Where(folder => !string.IsNullOrEmpty(folder)).ToList();

        public string SystemFolder => Environment.GetFolderPath(Environment.SpecialFolder.System);
    }
}
