using System.Windows;
using Wpf.Ui.Controls;

namespace Softwareverwaltung.App.Views;

/// <summary>Einmalige Zustimmung zur Vereinbarung der winget-Quelle „msstore“. „Abbrechen“ ist Standard (Enter).</summary>
public partial class StoreAgreementWindow : FluentWindow
{
    public StoreAgreementWindow()
    {
        InitializeComponent();
    }

    private void OnAccept(object sender, RoutedEventArgs e) => DialogResult = true;

    private void OnCancel(object sender, RoutedEventArgs e) => DialogResult = false;
}
