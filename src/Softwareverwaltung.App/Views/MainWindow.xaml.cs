using System.ComponentModel;
using System.Windows;
using Softwareverwaltung.App.Localization;
using Softwareverwaltung.App.ViewModels;
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

    /// <summary>
    /// Läuft die Warteschlange, erst warnen (Standard „Abbrechen“). Bei Bestätigung wird die laufende
    /// Aktion fertig, der Rest abgebrochen und protokolliert; danach schließt die App von selbst.
    /// </summary>
    protected override void OnClosing(CancelEventArgs e)
    {
        if (DataContext is ShellViewModel { Programs: { QueueRunning: true } programs })
        {
            e.Cancel = true;
            var answer = System.Windows.MessageBox.Show(this, AppText.Get("QueueCloseWarning"), AppText.Get("QueueCloseTitle"),
                System.Windows.MessageBoxButton.OKCancel, MessageBoxImage.Warning, System.Windows.MessageBoxResult.Cancel);
            if (answer == System.Windows.MessageBoxResult.OK)
            {
                programs.QueueFinished += (_, _) => Dispatcher.BeginInvoke(Close);
                programs.CancelQueue();
            }
            return;
        }
        base.OnClosing(e);
    }
}
