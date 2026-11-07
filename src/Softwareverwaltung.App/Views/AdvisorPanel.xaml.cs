using System.Collections.Specialized;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using Softwareverwaltung.App.Services;
using Softwareverwaltung.App.ViewModels;

namespace Softwareverwaltung.App.Views;

/// <summary>
/// Seitenleiste des KI-Beraters. Nur Darstellung: Breite ziehen, Eingabetaste sendet, Verlauf folgt der
/// neuesten Nachricht. Alles andere steht im <see cref="AdvisorChatViewModel"/>.
/// </summary>
public partial class AdvisorPanel : UserControl
{
    // Breite, die links neben der Seitenleiste für Liste und Einstellungen mindestens bleibt.
    private const double MinVisibleContent = 360;

    private AdvisorChatViewModel? _viewModel;

    public AdvisorPanel()
    {
        InitializeComponent();
        DataContextChanged += (_, _) => Attach(DataContext as AdvisorChatViewModel);
        Loaded += (_, _) =>
        {
            // Schmaleres Fenster: Seitenleiste mitschrumpfen lassen, damit links genug Platz bleibt.
            if (Window.GetWindow(this) is { } window)
            {
                window.SizeChanged -= OnWindowSizeChanged;
                window.SizeChanged += OnWindowSizeChanged;
            }
            ApplyWidth();
        };
    }

    private void Attach(AdvisorChatViewModel? viewModel)
    {
        if (_viewModel is not null)
        {
            _viewModel.PropertyChanged -= OnViewModelChanged;
            _viewModel.Entries.CollectionChanged -= OnEntriesChanged;
        }
        _viewModel = viewModel;
        if (viewModel is not null)
        {
            viewModel.PropertyChanged += OnViewModelChanged;
            viewModel.Entries.CollectionChanged += OnEntriesChanged;
            ApplyWidth();
        }
    }

    private void OnWindowSizeChanged(object sender, SizeChangedEventArgs e) => ApplyWidth();

    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AdvisorChatViewModel.PanelWidth))
        {
            ApplyWidth();
        }
        else if (e.PropertyName == nameof(AdvisorChatViewModel.IsOpen) && _viewModel?.IsOpen == true)
        {
            // Beim Öffnen gleich ins Eingabefeld, damit man lostippen kann.
            Dispatcher.BeginInvoke(() => QuestionBox.Focus());
        }
    }

    private void OnEntriesChanged(object? sender, NotifyCollectionChangedEventArgs e) =>
        Dispatcher.BeginInvoke(() => History.ScrollToEnd());

    /// <summary>Eingabetaste sendet, Umschalt+Eingabetaste macht eine neue Zeile.</summary>
    private void OnQuestionKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && (Keyboard.Modifiers & ModifierKeys.Shift) == 0)
        {
            e.Handled = true;
            if (_viewModel?.SendCommand.CanExecute(null) == true)
            {
                _viewModel.SendCommand.Execute(null);
            }
        }
    }

    /// <summary>Ziehen am linken Rand: neue Breite live anzeigen, gespeichert wird erst beim Loslassen.</summary>
    private void OnResizeDelta(object sender, DragDeltaEventArgs e) => Root.Width = ClampWidth(Root.ActualWidth - e.HorizontalChange);

    private void OnResizeCompleted(object sender, DragCompletedEventArgs e)
    {
        if (_viewModel is not null)
        {
            _viewModel.PanelWidth = AppUiSettings.ClampAdvisorWidth(Root.ActualWidth);
        }
    }

    private void ApplyWidth()
    {
        if (_viewModel is not null)
        {
            Root.Width = ClampWidth(_viewModel.PanelWidth);
        }
    }

    /// <summary>Im erlaubten Bereich und so, dass links daneben genug Platz bleibt.</summary>
    private double ClampWidth(double width)
    {
        var window = Window.GetWindow(this);
        var available = window is null ? AppUiSettings.MaxAdvisorPanelWidth : window.ActualWidth - MinVisibleContent;
        var max = Math.Max(AppUiSettings.MinAdvisorPanelWidth, Math.Min(AppUiSettings.MaxAdvisorPanelWidth, available));
        return Math.Clamp(width, AppUiSettings.MinAdvisorPanelWidth, max);
    }
}
