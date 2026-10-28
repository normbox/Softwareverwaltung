using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using Softwareverwaltung.App.ViewModels;

namespace Softwareverwaltung.App.Views;

public partial class ProgramsView : UserControl
{
    public ProgramsView()
    {
        InitializeComponent();
    }

    /// <summary>Zweiter Klick auf die aufgeklappte Zeile klappt sie zu; Klicks in die Details selbst nicht.</summary>
    private void OnGridPreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is not DependencyObject source || DataContext is not MainViewModel viewModel)
        {
            return;
        }
        var row = FindAncestor<DataGridRow>(source);
        if (row is null || !row.IsSelected || FindAncestor<DataGridDetailsPresenter>(source) is not null)
        {
            return;
        }
        viewModel.CloseDetailsCommand.Execute(null);
        e.Handled = true;
    }

    private static T? FindAncestor<T>(DependencyObject? element) where T : DependencyObject
    {
        // Text (Run) gehört nur zum logischen Baum, Steuerelemente zum visuellen.
        while (element is not null and not T)
        {
            element = element is Visual ? VisualTreeHelper.GetParent(element) : LogicalTreeHelper.GetParent(element);
        }
        return element as T;
    }
}
