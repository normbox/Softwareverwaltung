using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace SoftwareInventory
{
    /// <summary>Prozess-ID der Gegenstelle einer Named Pipe (Prüfung des Helfers mit Administratorrechten).</summary>
    public static class PipeInterop
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe, out uint clientProcessId);
    }
}
