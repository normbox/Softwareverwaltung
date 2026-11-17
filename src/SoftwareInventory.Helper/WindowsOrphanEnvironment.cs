#nullable disable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace SoftwareInventory.Helper
{
    /// <summary>
    /// Maschinenweite Ordner für Umgebungsvariablen. Die Werte stammen aus Windows-Funktionen (bekannte Ordner,
    /// Systemverzeichnis), nie aus der Umgebung des Prozesses: Die kommt im erhöhten Helfer auch aus HKCU\Environment
    /// und ließe sich vom Benutzer ohne Adminrechte umbiegen (z. B. ProgramFiles=C:\Nix).
    /// </summary>
    public sealed class MachineFolders
    {
        /// <summary>Die erlaubten Variablen; jede andere macht einen Pfad nicht auswertbar.</summary>
        public static readonly string[] Names =
        {
            "ProgramFiles", "ProgramFiles(x86)", "ProgramW6432", "CommonProgramFiles", "CommonProgramFiles(x86)",
            "CommonProgramW6432", "SystemRoot", "windir", "SystemDrive", "ProgramData",
        };

        private static readonly Regex Variable = new Regex("%([^%]+)%", RegexOptions.Compiled);

        private readonly Dictionary<string, string> _values;

        public MachineFolders(IDictionary<string, string> values)
        {
            _values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var name in Names)
            {
                if (values.TryGetValue(name, out var value) && !string.IsNullOrEmpty(value))
                {
                    _values[name] = value.TrimEnd('\\');
                }
            }
        }

        /// <summary>Die Werte dieses Rechners (64-Bit-Prozess: ProgramFiles ist der 64-Bit-Ordner).</summary>
        public static MachineFolders Current()
        {
            var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            var common = Environment.GetFolderPath(Environment.SpecialFolder.CommonProgramFiles);
            var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            return new MachineFolders(new Dictionary<string, string>
            {
                ["ProgramFiles"] = programFiles,
                ["ProgramW6432"] = programFiles,
                ["ProgramFiles(x86)"] = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                ["CommonProgramFiles"] = common,
                ["CommonProgramW6432"] = common,
                ["CommonProgramFiles(x86)"] = Environment.GetFolderPath(Environment.SpecialFolder.CommonProgramFilesX86),
                ["SystemRoot"] = windows,
                ["windir"] = windows,
                ["SystemDrive"] = Path.GetPathRoot(Environment.SystemDirectory),
                ["ProgramData"] = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            });
        }

        public string this[string name] => _values.TryGetValue(name, out var value) ? value : null;

        /// <summary>Setzt nur die erlaubten Variablen ein; null, wenn eine andere oder eine ohne Wert vorkommt.</summary>
        public string Expand(string text)
        {
            if (text is null)
            {
                return null;
            }
            var unknown = false;
            var result = Variable.Replace(text, m =>
            {
                if (_values.TryGetValue(m.Groups[1].Value, out var value))
                {
                    return value;
                }
                unknown = true;
                return m.Value;
            });
            return unknown ? null : result;
        }
    }

    /// <summary>
    /// Die echte Umsetzung von <see cref="IOrphanEnvironment"/> über das Windows-Dateisystem, für den erhöhten Helfer:
    /// nur maschinenweite Variablen (<see cref="MachineFolders"/>).
    /// </summary>
    public sealed class WindowsOrphanEnvironment : IOrphanEnvironment
    {
        private readonly MachineFolders _folders;

        public WindowsOrphanEnvironment()
            : this(MachineFolders.Current())
        {
        }

        public WindowsOrphanEnvironment(MachineFolders folders)
        {
            _folders = folders;
        }

        public string ExpandVariables(string text) => _folders.Expand(text);

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
            _folders["ProgramW6432"],
            _folders["CommonProgramW6432"],
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
            _folders["windir"],
        }.Where(folder => !string.IsNullOrEmpty(folder)).ToList();

        public string SystemFolder => Environment.GetFolderPath(Environment.SpecialFolder.System);
    }
}
