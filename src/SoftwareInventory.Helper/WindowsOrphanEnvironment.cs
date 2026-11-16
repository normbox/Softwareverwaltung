#nullable disable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace SoftwareInventory.Helper
{
    /// <summary>Die echte Umsetzung von <see cref="IOrphanEnvironment"/> über das Windows-Dateisystem.</summary>
    public sealed class WindowsOrphanEnvironment : IOrphanEnvironment
    {
        public string ExpandVariables(string text) => Environment.ExpandEnvironmentVariables(text);

        public bool PathExists(string path) => File.Exists(path) || Directory.Exists(path);

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
