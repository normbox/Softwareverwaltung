using System.Diagnostics;
using System.Windows;
using Softwareverwaltung.App.Localization;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Views;

namespace Softwareverwaltung.App.Services;

public interface IConfirmationService
{
    /// <summary>Zeigt den geplanten Befehl und fragt, ob er ausgeführt werden soll.</summary>
    bool Confirm(ActionOutcome plan);

    /// <summary>Fragt vor einem Scan ohne Zwischenspeicher nach (nur ohne NVD-Schlüssel), mit geschätzter Dauer.</summary>
    Task<bool> ConfirmRefreshAsync(RefreshEstimate estimate);
}

public sealed class ConfirmationService : IConfirmationService
{
    public bool Confirm(ActionOutcome plan)
    {
        var dialog = new ConfirmActionWindow { DataContext = plan, Owner = Application.Current?.MainWindow };
        return dialog.ShowDialog() == true;
    }

    public async Task<bool> ConfirmRefreshAsync(RefreshEstimate estimate)
    {
        var duration = estimate.Seconds < 120
            ? AppText.Format("RefreshDurationSeconds", estimate.Seconds)
            : AppText.Format("RefreshDurationMinutes", (int)Math.Ceiling(estimate.Seconds / 60.0));
        var box = new Wpf.Ui.Controls.MessageBox
        {
            Title = AppText.Get("RefreshConfirmTitle"),
            Content = AppText.Format("RefreshConfirmText", duration, estimate.NvdRequests),
            PrimaryButtonText = AppText.Get("RefreshConfirmStart"),
            SecondaryButtonText = AppText.Get("RefreshConfirmGetKey"),
            CloseButtonText = AppText.Get("CommonCancel"),
            // Über der App zentriert (auch auf einem zweiten Bildschirm) und breit genug für alle drei Buttons.
            Owner = Application.Current?.MainWindow,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Width = 560,
            MaxWidth = 560,
        };
        var result = await box.ShowDialogAsync();
        if (result == Wpf.Ui.Controls.MessageBoxResult.Secondary)
        {
            // Nur die feste Seite der NVD zum Beantragen; eingetragen wird unter Einstellungen > API-Schlüssel.
            Process.Start(new ProcessStartInfo(NvdKeyUrl) { UseShellExecute = true })?.Dispose();
            return false;
        }
        return result == Wpf.Ui.Controls.MessageBoxResult.Primary;
    }

    public const string NvdKeyUrl = "https://nvd.nist.gov/developers/request-an-api-key";
}
