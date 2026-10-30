using System.Management.Automation;
using Softwareverwaltung.App.Localization;

namespace Softwareverwaltung.App.Models;

/// <summary>
/// Abbild von SoftwareInventory.RefreshEstimate: geschätzte Dauer eines Scans ohne Zwischenspeicher.
/// ConfirmReason kommt vom Modul: NvdWithoutKey, LongDuration oder null.
/// </summary>
public sealed record RefreshEstimate(int NvdRequests, int Seconds, bool NeedsConfirmation, string? ConfirmReason = null)
{
    public const string ReasonLongDuration = "LongDuration";

    /// <summary>Geschätzte Dauer als Text, z. B. „etwa 28 Minuten“.</summary>
    public string DurationText => Seconds < 120
        ? AppText.Format("RefreshDurationSeconds", Seconds)
        : AppText.Format("RefreshDurationMinutes", (int)Math.Ceiling(Seconds / 60.0));

    public static RefreshEstimate FromPs(PSObject obj) => new(
        Convert.ToInt32(obj.Properties["NvdRequests"]?.Value ?? 0, System.Globalization.CultureInfo.InvariantCulture),
        Convert.ToInt32(obj.Properties["Seconds"]?.Value ?? 0, System.Globalization.CultureInfo.InvariantCulture),
        obj.Properties["NeedsConfirmation"]?.Value is true,
        obj.Properties["ConfirmReason"]?.Value?.ToString());
}
