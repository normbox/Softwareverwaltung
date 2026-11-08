using System;
using System.Threading;

namespace SoftwareInventory
{
    /// <summary>
    /// Läuft gerade eine Windows-Installer-Transaktion? Windows hält dafür den Mutex Global\_MSIExecute.
    /// Er wird nur geöffnet, nie in Besitz genommen; eine laufende Installation wird dadurch nicht aufgehalten.
    /// </summary>
    public static class InstallerActivity
    {
        private const string MutexName = @"Global\_MSIExecute";

        public static bool IsWindowsInstallerBusy() => IsBusy(() => Mutex.OpenExisting(MutexName).Dispose());

        /// <summary>Getrennt vom Öffnen, damit sich „Zugriff verweigert“ testen lässt: Der Mutex existiert dann, also läuft etwas.</summary>
        public static bool IsBusy(Action open)
        {
            try
            {
                open();
                return true;
            }
            catch (WaitHandleCannotBeOpenedException)
            {
                return false;
            }
            catch (UnauthorizedAccessException)
            {
                return true;
            }
        }
    }
}
