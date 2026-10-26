using System.Windows;
using System.Windows.Threading;
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
        var programs = new MainViewModel(new InventoryService(_host), new ActionService(_host), new ConfirmationService());
        var viewModel = new ShellViewModel(programs, new SettingsViewModel(new SettingsService(_host), new FolderPicker()));
        var window = new MainWindow { DataContext = viewModel };
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
        var where = path is null ? "" : $"{Environment.NewLine}{Environment.NewLine}Details stehen in:{Environment.NewLine}{path}";
        MessageBox.Show($"{e.Exception.GetType().Name}: {e.Exception.Message}{where}",
            "Softwareverwaltung: unerwarteter Fehler", MessageBoxButton.OK, MessageBoxImage.Error);
        e.Handled = true;
    }
}
