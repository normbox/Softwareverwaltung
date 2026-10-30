using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using Softwareverwaltung.App.Services;
using Softwareverwaltung.App.ViewModels;

namespace Softwareverwaltung.App.Views;

public partial class ProgramsView : UserControl
{
    // Breite der Liste, die neben dem Detailfeld mindestens sichtbar bleibt.
    private const double MinVisibleList = 120;

    public ProgramsView()
    {
        InitializeComponent();
        DataContextChanged += (_, _) =>
        {
            if (DataContext is MainViewModel viewModel)
            {
                viewModel.PropertyChanged += (_, e) =>
                {
                    if (e.PropertyName is nameof(MainViewModel.IsDetailsOpen) or nameof(MainViewModel.DetailsWidthFraction))
                    {
                        UpdateDetailsWidth();
                    }
                };
                UpdateDetailsWidth();
            }
        };
    }

    /// <summary>Klick auf eine Zeile öffnet das Detailfeld; Häkchen der Warteschlange schalten nur um.</summary>
    private void OnGridPreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is not DependencyObject source || DataContext is not MainViewModel viewModel)
        {
            return;
        }
        if (FindAncestor<CheckBox>(source) is { IsEnabled: true } box)
        {
            box.IsChecked = box.IsChecked != true;
            e.Handled = true;
            return;
        }
        if (FindAncestor<DataGridRow>(source) is { } row)
        {
            // Auswahl erst setzen, dann öffnen; der Fokus bleibt in der Liste.
            viewModel.SelectedItem = row.Item as Models.SoftwareItem;
            viewModel.OpenDetailsCommand.Execute(null);
        }
    }

    /// <summary>Eingabe öffnet das Detailfeld für die ausgewählte Zeile (statt in die nächste Zeile zu springen).</summary>
    private void OnGridPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && DataContext is MainViewModel viewModel && viewModel.SelectedItem is not null)
        {
            viewModel.OpenDetailsCommand.Execute(null);
            e.Handled = true;
        }
    }

    private void OnListHostSizeChanged(object sender, SizeChangedEventArgs e) => UpdateDetailsWidth();

    /// <summary>Ziehen am linken Rand: neue Breite live anzeigen, gespeichert wird erst beim Loslassen.</summary>
    private void OnDetailsResizeDelta(object sender, DragDeltaEventArgs e)
    {
        DetailsPanel.Width = ClampWidth(DetailsPanel.ActualWidth - e.HorizontalChange);
    }

    private void OnDetailsResizeCompleted(object sender, DragCompletedEventArgs e)
    {
        if (DataContext is MainViewModel viewModel && ListHost.ActualWidth > 0)
        {
            viewModel.DetailsWidthFraction = AppUiSettings.ClampFraction(DetailsPanel.ActualWidth / ListHost.ActualWidth);
        }
    }

    private void UpdateDetailsWidth()
    {
        if (DataContext is MainViewModel viewModel && ListHost.ActualWidth > 0)
        {
            DetailsPanel.Width = ClampWidth(ListHost.ActualWidth * viewModel.DetailsWidthFraction);
        }
    }

    private double ClampWidth(double width)
    {
        var max = Math.Max(AppUiSettings.MinDetailsWidth, ListHost.ActualWidth - MinVisibleList);
        return Math.Clamp(width, Math.Min(AppUiSettings.MinDetailsWidth, max), max);
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
