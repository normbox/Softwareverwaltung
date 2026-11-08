using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace SoftwareInventory
{
    /// <summary>Ein mit UAC gestarteter Prozess. Bietet nur, was das Modul braucht (wie System.Diagnostics.Process).</summary>
    public sealed class ElevatedProcess : IDisposable
    {
        private readonly SafeProcessHandle _handle;

        internal ElevatedProcess(SafeProcessHandle handle, int id)
        {
            _handle = handle;
            Id = id;
        }

        public int Id { get; }

        public bool HasExited => WaitForSingleObject(_handle, 0) == 0;

        public int ExitCode
        {
            get
            {
                if (!GetExitCodeProcess(_handle, out var code))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
                return unchecked((int)code);
            }
        }

        public void Dispose() => _handle.Dispose();

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint WaitForSingleObject(SafeProcessHandle handle, uint milliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetExitCodeProcess(SafeProcessHandle handle, out uint exitCode);
    }

    /// <summary>
    /// Startet einen Prozess mit UAC-Abfrage und dem Fenster der App als Besitzer. Start-Process kennt
    /// kein Besitzerfenster; ohne eines kann die Abfrage nur in der Taskleiste blinken.
    /// </summary>
    public static class ElevationInterop
    {
        private const uint SeeMaskNoCloseProcess = 0x00000040;
        private const uint SeeMaskNoAsync = 0x00000100;
        private const uint SeeMaskFlagNoUi = 0x00000400;
        private const int SwHide = 0;
        private const int SwShowNormal = 1;

        /// <summary>Kehrt zurück, wenn die Abfrage beantwortet ist. Ablehnen ergibt Win32Exception 1223.</summary>
        public static ElevatedProcess Start(string file, string arguments, IntPtr owner) =>
            Run(file, arguments, owner, null, SwShowNormal);

        /// <summary>Für Werkzeuge aus System32: ohne Fenster und mit System32 als Arbeitsordner, damit nichts aus einem anderen Ordner geladen wird.</summary>
        public static ElevatedProcess StartTool(string file, string arguments, IntPtr owner, string directory) =>
            Run(file, arguments, owner, directory, SwHide);

        private static ElevatedProcess Run(string file, string arguments, IntPtr owner, string? directory, int show)
        {
            ElevatedProcess? result = null;
            Exception? failure = null;
            // Die Shell erwartet einen STA-Thread; der Thread der PowerShell-Engine ist das nicht immer.
            var thread = new Thread(() =>
            {
                try
                {
                    result = StartCore(file, arguments, owner, directory, show);
                }
                catch (Exception ex)
                {
                    failure = ex;
                }
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.IsBackground = true;
            thread.Start();
            thread.Join();
            if (failure is not null)
            {
                throw failure;
            }
            return result!;
        }

        private static ElevatedProcess StartCore(string file, string arguments, IntPtr owner, string? directory, int show)
        {
            var info = new ShellExecuteInfo
            {
                cbSize = Marshal.SizeOf<ShellExecuteInfo>(),
                fMask = SeeMaskNoCloseProcess | SeeMaskNoAsync | SeeMaskFlagNoUi,
                hwnd = owner,
                lpVerb = "runas",
                lpFile = file,
                lpParameters = arguments,
                lpDirectory = directory!,
                nShow = show,
            };
            if (!ShellExecuteExW(ref info))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            var handle = new SafeProcessHandle(info.hProcess, ownsHandle: true);
            return new ElevatedProcess(handle, (int)GetProcessId(handle));
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct ShellExecuteInfo
        {
            public int cbSize;
            public uint fMask;
            public IntPtr hwnd;
            public string lpVerb;
            public string lpFile;
            public string lpParameters;
            public string lpDirectory;
            public int nShow;
            public IntPtr hInstApp;
            public IntPtr lpIDList;
            public string lpClass;
            public IntPtr hkeyClass;
            public uint dwHotKey;
            public IntPtr hIconOrMonitor;
            public IntPtr hProcess;
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool ShellExecuteExW(ref ShellExecuteInfo info);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint GetProcessId(SafeProcessHandle handle);
    }
}
