using System.Collections;
using System.Management.Automation;

namespace Softwareverwaltung.App.Models;

public enum Rating
{
    Red,
    Yellow,
    Gray,
    Green,
}

/// <summary>
/// Ein Programm in der Hauptliste, übernommen aus SoftwareInventory.SecurityRating.
/// Nur Abbildung der Modulfelder, keine eigene Bewertung.
/// </summary>
public sealed record SoftwareItem
{
    public required string Name { get; init; }
    public string? Publisher { get; init; }
    public string? InstalledVersion { get; init; }
    public string? LatestVersion { get; init; }
    /// <summary>Neueste Version stammt aus einer unbestätigten Quelle (z. B. winget-Suche nach Name).</summary>
    public bool LatestVersionUnconfirmed { get; init; }
    public bool UpdateAvailable { get; init; }
    public Rating Rating { get; init; } = Rating.Gray;
    public IReadOnlyList<string> Reasons { get; init; } = [];
    /// <summary>Anzahl der Lücken; null, wenn nicht auf Lücken geprüft wurde (Ampel Grau).</summary>
    public int? VulnerabilityCount { get; init; }
    public string Sources { get; init; } = "";
    /// <summary>Originalobjekt des Moduls, für spätere Aktionen (Update-Software, Uninstall-Software).</summary>
    public PSObject? Source { get; init; }

    public bool HasSecurityRisk => Rating == Rating.Red || VulnerabilityCount > 0;

    public string ReasonText => string.Join(Environment.NewLine, Reasons);

    public static SoftwareItem FromRating(PSObject rating)
    {
        var record = Get<PSObject>(rating, "Record");
        var update = Get<PSObject>(rating, "UpdateStatus");
        var vulnerability = Get<PSObject>(rating, "VulnerabilityStatus");
        var latest = GetString(rating, "LatestVersion");

        return new SoftwareItem
        {
            Name = GetString(rating, "Name") ?? "(ohne Namen)",
            Publisher = record is null ? null : GetString(record, "Publisher"),
            InstalledVersion = GetString(rating, "Version"),
            LatestVersion = latest,
            LatestVersionUnconfirmed = latest is not null && update is not null && GetString(update, "Confirmed") == bool.FalseString,
            UpdateAvailable = update is not null && GetString(update, "Status") == "Outdated",
            Rating = Enum.TryParse<Rating>(GetString(rating, "Rating"), out var r) ? r : Rating.Gray,
            Reasons = GetStrings(rating, "Reasons"),
            // Hinweise ohne Ampelwirkung (Informational) zählen nicht als Lücke.
            VulnerabilityCount = vulnerability is null || GetString(vulnerability, "Status") != "Checked" ? null
                : GetObjects(vulnerability, "Vulnerabilities").Count(v => GetString(v, "Assessment") is "Affected" or "PossiblyAffected"),
            Sources = record is null ? "" : string.Join(", ", GetStrings(record, "Sources")),
            Source = rating,
        };
    }

    private static T? Get<T>(PSObject obj, string name) where T : class
    {
        var value = obj.Properties[name]?.Value;
        return value switch
        {
            T t => t,
            PSObject { BaseObject: T inner } => inner,
            _ => null,
        };
    }

    private static string? GetString(PSObject obj, string name)
    {
        var value = obj.Properties[name]?.Value;
        var text = value is PSObject ps ? ps.BaseObject?.ToString() : value?.ToString();
        return string.IsNullOrWhiteSpace(text) ? null : text;
    }

    private static IEnumerable<PSObject> GetObjects(PSObject obj, string name) => obj.Properties[name]?.Value switch
    {
        null => [],
        string => [],
        IEnumerable list => list.Cast<object?>().Where(o => o is not null).Select(PSObject.AsPSObject!),
        var single => [PSObject.AsPSObject(single)],
    };

    private static IReadOnlyList<string> GetStrings(PSObject obj, string name) => obj.Properties[name]?.Value switch
    {
        null => [],
        string s => [s],
        IEnumerable list => list.Cast<object?>().Select(o => o?.ToString()).OfType<string>().Where(s => s.Length > 0).ToList(),
        var single => [single.ToString() ?? ""],
    };
}
