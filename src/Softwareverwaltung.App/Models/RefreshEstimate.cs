using System.Management.Automation;

namespace Softwareverwaltung.App.Models;

/// <summary>Abbild von SoftwareInventory.RefreshEstimate: geschätzte Dauer eines Scans ohne Zwischenspeicher.</summary>
public sealed record RefreshEstimate(int NvdRequests, int Seconds, bool NeedsConfirmation)
{
    public static RefreshEstimate FromPs(PSObject obj) => new(
        Convert.ToInt32(obj.Properties["NvdRequests"]?.Value ?? 0, System.Globalization.CultureInfo.InvariantCulture),
        Convert.ToInt32(obj.Properties["Seconds"]?.Value ?? 0, System.Globalization.CultureInfo.InvariantCulture),
        obj.Properties["NeedsConfirmation"]?.Value is true);
}
