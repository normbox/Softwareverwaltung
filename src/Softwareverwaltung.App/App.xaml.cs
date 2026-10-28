using System.Windows;
using System.Windows.Threading;
using Softwareverwaltung.App.Localization;
using Softwareverwaltung.App.Services;
using Softwareverwaltung.App.ViewModels;
using Softwareverwaltung.App.Views;

namespace Softwareverwaltung.App;

public partial class App : Application
{
    private PowerShellHost? _host;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += OnUnhandledException;
        // Fehler außerhalb des UI-Threads: nur protokollieren, damit sie sich nachvollziehen lassen.
        AppDomain.CurrentDomain.UnhandledException += (_, args) => ErrorLog.Write("AppDomain", args.ExceptionObject as Exception);
        TaskScheduler.UnobservedTaskException += (_, args) => ErrorLog.Write("Task", args.Exception);

        _host = new PowerShellHost();
        var programs = new MainViewModel(new InventoryService(_host), new ActionService(_host), new ConfirmationService(), shell: new ShellService());
        var settings = new SettingsViewModel(new SettingsService(_host), new FolderPicker());
        var viewModel = new ShellViewModel(programs, settings);
        var window = new MainWindow { DataContext = viewModel };
        // Laufwerke und USB-Sticks live: die Liste in den Einstellungen folgt ohne Neustart.
        var drives = new DriveChangeWatcher();
        drives.DrivesChanged += async (_, _) => await settings.RefreshDrivesAsync();
        drives.Attach(window);
        window.Show();
        // Fehler beim Laden der Module zeigen die ViewModels selbst als Hinweis an.
        _ = viewModel.InitializeAsync();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _host?.Dispose();
        base.OnExit(e);
    }

    private static void OnUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        var path = ErrorLog.Write("UI", e.Exception);
        var where = path is null ? "" : Environment.NewLine + Environment.NewLine + AppText.Format("ErrorDetailsIn", Environment.NewLine + path);
        MessageBox.Show($"{e.Exception.GetType().Name}: {e.Exception.Message}{where}",
            AppText.Get("ErrorUnexpectedTitle"), MessageBoxButton.OK, MessageBoxImage.Error);
        e.Handled = true;
    }
}
