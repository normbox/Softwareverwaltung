using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;

namespace Softwareverwaltung.App.Services;

/// <summary>
/// Meldet, wenn ein Laufwerk oder USB-Stick dazukommt oder entfernt wird (Windows-Nachricht
/// WM_DEVICECHANGE an das Hauptfenster). Mehrere Meldungen kurz hintereinander werden zusammengefasst.
/// </summary>
public sealed class DriveChangeWatcher
{
    private const int WmDeviceChange = 0x0219;
    private const int DbtDeviceArrival = 0x8000;
    private const int DbtDeviceRemoveComplete = 0x8004;

    private readonly DispatcherTimer _debounce;

    public DriveChangeWatcher()
    {
        _debounce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(700) };
        _debounce.Tick += (_, _) =>
        {
            _debounce.Stop();
            DrivesChanged?.Invoke(this, EventArgs.Empty);
        };
    }

    public event EventHandler? DrivesChanged;

    /// <summary>Am Hauptfenster anmelden, sobald es ein Fensterhandle hat.</summary>
    public void Attach(Window window)
    {
        void Hook()
        {
            var source = HwndSource.FromHwnd(new WindowInteropHelper(window).Handle);
            source?.AddHook(WndProc);
        }

        if (new WindowInteropHelper(window).Handle != IntPtr.Zero)
        {
            Hook();
        }
        else
        {
            window.SourceInitialized += (_, _) => Hook();
        }
    }

    /// <summary>Für Tests und für die Nachricht selbst: eine Änderung melden (wird zusammengefasst).</summary>
    public void NotifyChanged()
    {
        _debounce.Stop();
        _debounce.Start();
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmDeviceChange && (wParam.ToInt32() == DbtDeviceArrival || wParam.ToInt32() == DbtDeviceRemoveComplete))
        {
            NotifyChanged();
        }
        return IntPtr.Zero;
    }
}
