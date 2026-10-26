using System.Windows;
using System.Windows.Controls;
using Softwareverwaltung.App.ViewModels;

namespace Softwareverwaltung.App.Views;

public partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
    }

    /// <summary>
    /// PasswordBox lässt sich nicht binden. Der Schlüssel geht als SecureString direkt an das Modul
    /// und wird danach aus dem Feld gelöscht.
    /// </summary>
    private async void OnSaveCredential(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: PasswordBox box, DataContext: CredentialItem item } || DataContext is not SettingsViewModel vm)
        {
            return;
        }
        using var secret = box.SecurePassword;
        await vm.SaveCredentialAsync(item, secret);
        box.Clear();
    }
}
