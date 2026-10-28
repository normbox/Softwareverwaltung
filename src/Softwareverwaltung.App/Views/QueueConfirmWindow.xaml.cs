using System.Windows;
using Wpf.Ui.Controls;

namespace Softwareverwaltung.App.Views;

/// <summary>Gemeinsame Bestätigung der Update-Warteschlange. „Abbrechen“ ist Standard (Enter), damit nichts aus Versehen läuft.</summary>
public partial class QueueConfirmWindow : FluentWindow
{
    public QueueConfirmWindow()
    {
        InitializeComponent();
    }

    private void OnStart(object sender, RoutedEventArgs e) => DialogResult = true;

    private void OnCancel(object sender, RoutedEventArgs e) => DialogResult = false;
}
