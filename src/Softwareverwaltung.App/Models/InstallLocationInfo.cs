using System.Management.Automation;

namespace Softwareverwaltung.App.Models;

/// <summary>
/// Abbild von SoftwareInventory.InstallLocation: Ordner mit Herkunft („laut Installer-Eintrag“,
/// „vermutlich, …“) oder, wenn unbekannt, der Grund. Ermittelt und bewertet wird im Modul.
/// </summary>
public sealed record InstallLocationInfo(string? Path, string? Note, string? Reason, bool CanOpen)
{
    public bool IsKnown => !string.IsNullOrEmpty(Path);

    public static InstallLocationInfo FromPs(PSObject obj) => new(
        ActionOutcome.Text(obj, "Path"),
        SoftwareItem.MessageText(obj.Properties["Note"]?.Value),
        SoftwareItem.MessageText(obj.Properties["Reason"]?.Value),
        obj.Properties["CanOpen"]?.Value is true);
}
