using System.Windows;
using Softwareverwaltung.App.ViewModels;
using Wpf.Ui.Controls;

namespace Softwareverwaltung.App.Views;

/// <summary>„CPE zuordnen“: Vorschläge und eigene Eingabe. „Abbrechen“ ist Standard (Enter).</summary>
public partial class CpeMappingWindow : FluentWindow
{
    public CpeMappingWindow()
    {
        InitializeComponent();
        DataContextChanged += (_, e) =>
        {
            if (e.OldValue is CpeMappingViewModel old)
            {
                old.CloseRequested -= OnCloseRequested;
            }
            if (e.NewValue is CpeMappingViewModel vm)
            {
                vm.CloseRequested += OnCloseRequested;
            }
        };
    }

    private void OnCloseRequested(object? sender, EventArgs e) => DialogResult = true;

    private void OnCancel(object sender, RoutedEventArgs e) => DialogResult = false;
}
