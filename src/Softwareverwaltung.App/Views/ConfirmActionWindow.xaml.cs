using System.Windows;
using Wpf.Ui.Controls;

namespace Softwareverwaltung.App.Views;

/// <summary>Bestätigung vor jeder Aktion. „Abbrechen“ ist Standard (Enter), damit nichts aus Versehen läuft.</summary>
public partial class ConfirmActionWindow : FluentWindow
{
    public ConfirmActionWindow()
    {
        InitializeComponent();
    }

    private void OnExecute(object sender, RoutedEventArgs e) => DialogResult = true;

    private void OnCancel(object sender, RoutedEventArgs e) => DialogResult = false;
}
