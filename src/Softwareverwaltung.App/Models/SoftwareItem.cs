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
    /// <summary>
    /// Anzahl der Lücken einschließlich „möglicherweise betroffen“; null, wenn nicht auf Lücken
    /// geprüft wurde und auch nichts gefunden ist (Ampel Grau).
    /// </summary>
    public int? VulnerabilityCount { get; init; }
    /// <summary>Davon „möglicherweise betroffen“ (Version nicht prüfbar).</summary>
    public int PossibleCount { get; init; }
    public IReadOnlyList<VulnerabilityItem> Vulnerabilities { get; init; } = [];
    /// <summary>KEV-Treffer, die für diese Version widerlegt sind, mit Begründung.</summary>
    public IReadOnlyList<string> Refuted { get; init; } = [];
    public string Sources { get; init; } = "";
    /// <summary>Originalobjekt des Moduls, für spätere Aktionen (Update-Software, Uninstall-Software).</summary>
    public PSObject? Source { get; init; }

    public bool HasSecurityRisk => Rating == Rating.Red || VulnerabilityCount > 0;

    public string ReasonText => string.Join(Environment.NewLine, Reasons);

    /// <summary>Erster Grund für die Spalte „Grund“; alle Gründe stehen im Tooltip und in den Details.</summary>
    public string ReasonSummary => Reasons.Count switch
    {
        0 => "",
        1 => Reasons[0],
        _ => $"{Reasons[0]} (+{Reasons.Count - 1})",
    };

    /// <summary>Text der Spalte „Lücken“, z. B. „2“, „1 möglich“ oder „2 + 1 möglich“.</summary>
    public string VulnerabilityText => VulnerabilityCount switch
    {
        null => "",
        int total when PossibleCount == 0 => total.ToString(System.Globalization.CultureInfo.InvariantCulture),
        int total when total == PossibleCount => $"{PossibleCount} möglich",
        int total => $"{total - PossibleCount} + {PossibleCount} möglich",
    };

    public static SoftwareItem FromRating(PSObject rating)
    {
        var record = Get<PSObject>(rating, "Record");
        var update = Get<PSObject>(rating, "UpdateStatus");
        var vulnerability = Get<PSObject>(rating, "VulnerabilityStatus");
        var latest = GetString(rating, "LatestVersion");
        // Hinweise ohne Ampelwirkung (Informational) zählen nicht als Lücke, „möglicherweise betroffen“ schon.
        var vulnerabilities = vulnerability is null ? [] : GetObjects(vulnerability, "Vulnerabilities").Select(VulnerabilityItem.FromPs).ToList();
        var counted = vulnerabilities.Where(v => v.Assessment is "Affected" or "PossiblyAffected").ToList();
        var checkedForVulnerabilities = vulnerability is not null && GetString(vulnerability, "Status") == "Checked";

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
            VulnerabilityCount = checkedForVulnerabilities || counted.Count > 0 ? counted.Count : null,
            PossibleCount = counted.Count(v => v.Assessment == "PossiblyAffected"),
            Vulnerabilities = vulnerabilities,
            Refuted = vulnerability is null ? [] : GetObjects(vulnerability, "Refuted").Select(r => GetString(r, "Note")).OfType<string>().ToList(),
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

/// <summary>Eine Lücke aus VulnerabilityStatus.Vulnerabilities, für die Detailansicht.</summary>
public sealed record VulnerabilityItem(string CveId, string? Assessment, string? Note, bool Kev, double? Score, double? Epss, Uri? Url, string? Description)
{
    public string AssessmentText => Assessment switch
    {
        "Affected" => "betroffen",
        "PossiblyAffected" => "möglicherweise betroffen",
        "Informational" => "Hinweis",
        _ => Assessment ?? "",
    };

    /// <summary>Kurzinfo hinter der CVE-Nummer, z. B. „betroffen · aktiv ausgenutzt (KEV) · CVSS 7.0 · EPSS 67 %“.</summary>
    public string Summary => string.Join(" · ", new[]
    {
        AssessmentText,
        Kev ? "aktiv ausgenutzt (KEV)" : null,
        Score is { } s ? $"CVSS {s.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture)}" : null,
        Epss is { } e ? "EPSS " + e.ToString("P0", System.Globalization.CultureInfo.GetCultureInfo("de-DE")) : null,
    }.Where(p => !string.IsNullOrEmpty(p)));

    public static VulnerabilityItem FromPs(PSObject obj)
    {
        var url = obj.Properties["Url"]?.Value?.ToString();
        return new VulnerabilityItem(
            obj.Properties["CveId"]?.Value?.ToString() ?? "",
            obj.Properties["Assessment"]?.Value?.ToString(),
            obj.Properties["Note"]?.Value?.ToString(),
            obj.Properties["Kev"]?.Value is true,
            Number(obj.Properties["Score"]?.Value),
            Number(obj.Properties["Epss"]?.Value),
            Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps ? uri : null,
            obj.Properties["Description"]?.Value?.ToString());
    }

    private static double? Number(object? value) => value switch
    {
        null => null,
        PSObject ps => Number(ps.BaseObject),
        double d => d,
        IConvertible c => c.ToDouble(System.Globalization.CultureInfo.InvariantCulture),
        _ => null,
    };
}
