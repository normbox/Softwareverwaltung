using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Softwareverwaltung.App.Models;

/// <summary>Unbestätigter CPE-Vorschlag aus dem NVD-Wörterbuch (Find-CpeCandidate).</summary>
public sealed record CpeCandidate(string Cpe, string? Vendor, string? Product, int Score, int Entries, Uri? Url)
{
    /// <summary>z. B. „Übereinstimmung 5 von 5 · 40 Einträge in der NVD“.</summary>
    public string DetailsText => Localization.AppText.Format("CpeCandidateDetails", Score, Entries);

    public static CpeCandidate FromPs(PSObject obj) => new(
        ActionOutcome.Text(obj, "Cpe") ?? "",
        ActionOutcome.Text(obj, "Vendor"),
        ActionOutcome.Text(obj, "Product"),
        int.TryParse(ActionOutcome.Text(obj, "Score"), out var score) ? score : 0,
        int.TryParse(ActionOutcome.Text(obj, "Entries"), out var entries) ? entries : 0,
        Uri.TryCreate(ActionOutcome.Text(obj, "Url"), UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps ? uri : null);
}

/// <summary>Ergebnis der Vorschlagssuche: Vorschläge oder ein Hinweis (z. B. NVD ist aus).</summary>
public sealed record CpeSearchResult(IReadOnlyList<CpeCandidate> Candidates, string? Hint);

/// <summary>Vorbereitetes GitHub-Issue für „Vorschlag melden“ (Get-CpeMappingReport).</summary>
public sealed record CpeReport(string Title, Uri Url, string Summary);

/// <summary>Was der Benutzer im Fenster „CPE zuordnen“ gewählt hat.</summary>
public sealed record CpeMappingChoice(string? Cpe, bool Remove)
{
    public static CpeMappingChoice Assign(string cpe) => new(cpe, false);

    public static readonly CpeMappingChoice RemoveMapping = new(null, true);
}

public static partial class CpeName
{
    /// <summary>Gleiche Regel wie Set-CpeMapping: cpe:2.3:a:hersteller:produkt ohne Version.</summary>
    public static bool IsValid(string? text) => text is not null && Pattern().IsMatch(text.Trim());

    [GeneratedRegex(@"^cpe:2\.3:[aho]:(\\.|[^:\\])+:(\\.|[^:\\])+$")]
    private static partial Regex Pattern();
}
