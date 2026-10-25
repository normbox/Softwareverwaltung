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

        _host = new PowerShellHost();
        var viewModel = new MainViewModel(new InventoryService(_host));
        var window = new MainWindow { DataContext = viewModel };
        window.Show();
        // Fehler beim Laden der Module zeigt das ViewModel selbst als Hinweis an.
        _ = viewModel.InitializeAsync();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _host?.Dispose();
        base.OnExit(e);
    }

    private static void OnUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        MessageBox.Show(e.Exception.Message, "Softwareverwaltung: unerwarteter Fehler", MessageBoxButton.OK, MessageBoxImage.Error);
        e.Handled = true;
    }
}
