using Wpf.Ui.Appearance;
using Wpf.Ui.Controls;

namespace Softwareverwaltung.App.Views;

public partial class MainWindow : FluentWindow
{
    public MainWindow()
    {
        InitializeComponent();
        // Hell/Dunkel und Akzentfarbe folgen den Windows-Einstellungen, auch während die App läuft.
        SystemThemeWatcher.Watch(this, WindowBackdropType.Mica, updateAccents: true);
        ApplicationThemeManager.ApplySystemTheme();
    }
}
