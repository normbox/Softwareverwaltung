using System.Collections;
using System.Management.Automation;
using Softwareverwaltung.App.Localization;

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
    public string? WingetId { get; init; }
    /// <summary>CPE-Namen ohne Version (Katalog oder eigene Zuordnung).</summary>
    public IReadOnlyList<string> CpeBase { get; init; } = [];
    /// <summary>Herkunft der CPE: „Catalog“ oder „User“ (vom Benutzer bestätigt).</summary>
    public string? CpeSource { get; init; }
    /// <summary>Grau mit Grund NoCpe: keine CPE, daher nicht auf Lücken geprüft.</summary>
    public bool NeedsCpe { get; init; }
    public bool HasUserCpe => CpeSource == "User";
    /// <summary>„CPE zuordnen“ anbieten: ohne CPE oder bei eigener Zuordnung (ändern, entfernen); Katalogeinträge nicht.</summary>
    public bool CanMapCpe => NeedsCpe || HasUserCpe;
    public string? CpeText => CpeBase.Count == 0 ? null : string.Join(", ", CpeBase) + (HasUserCpe ? " " + AppText.Get("CpeUserConfirmed") : "");
    public string? InstallLocation { get; init; }
    /// <summary>Kurzbeschreibung für die Details, z. B. „MSI · für alle Benutzer · X64“.</summary>
    public string? InstallInfo { get; init; }
    /// <summary>Originalobjekt des Moduls, für spätere Aktionen (Update-Software, Uninstall-Software).</summary>
    public PSObject? Source { get; init; }
    /// <summary>Ältere der beiden Online-Prüfungen (UTC); null, wenn nichts online geprüft wurde.</summary>
    public DateTime? CheckedAt { get; init; }
    public DateTime? UpdateCheckedAt { get; init; }
    public DateTime? VulnerabilityCheckedAt { get; init; }
    /// <summary>Daten älter als die eingestellte Haltbarkeit (z. B. offline nur Zwischenspeicher); dezent kennzeichnen.</summary>
    public bool CheckStale { get; init; }
    /// <summary>Häkchen für die Update-Warteschlange; nur bei verfügbarem Update wählbar.</summary>
    public QueueSelection Queue { get; } = new();

    /// <summary>Spalte „Geprüft“, z. B. „vor 2 h“.</summary>
    public string CheckedText => FormatAge(CheckedAt, DateTime.UtcNow);

    /// <summary>Beide Zeitpunkte und, falls veraltet, der Hinweis darauf.</summary>
    public string? CheckedTooltip
    {
        get
        {
            var lines = new List<string>();
            if (UpdateCheckedAt is { } u)
            {
                lines.Add(AppText.Format("CheckedTooltipUpdate", u.ToLocalTime()));
            }
            if (VulnerabilityCheckedAt is { } v)
            {
                lines.Add(AppText.Format("CheckedTooltipVulnerabilities", v.ToLocalTime()));
            }
            if (CheckStale)
            {
                lines.Add(AppText.Get("CheckedTooltipStale"));
            }
            return lines.Count == 0 ? null : string.Join(Environment.NewLine, lines);
        }
    }

    public static string FormatAge(DateTime? at, DateTime now)
    {
        if (at is not { } time)
        {
            return "";
        }
        var age = now - time.ToUniversalTime();
        return age.TotalMinutes switch
        {
            < 1 => AppText.Get("CheckedJustNow"),
            < 60 => AppText.Format("CheckedMinutes", (int)age.TotalMinutes),
            < 48 * 60 => AppText.Format("CheckedHours", (int)age.TotalHours),
            _ => AppText.Format("CheckedDays", (int)age.TotalDays),
        };
    }

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
        int total when total == PossibleCount => AppText.Format("VulnerabilitiesPossible", PossibleCount),
        int total => AppText.Format("VulnerabilitiesAffectedAndPossible", total - PossibleCount, PossibleCount),
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
            Name = GetString(rating, "Name") ?? AppText.Get("ProgramNoName"),
            Publisher = record is null ? null : GetString(record, "Publisher"),
            InstalledVersion = GetString(rating, "Version"),
            LatestVersion = latest,
            LatestVersionUnconfirmed = latest is not null && update is not null && GetString(update, "Confirmed") == bool.FalseString,
            UpdateAvailable = update is not null && GetString(update, "Status") == "Outdated",
            Rating = Enum.TryParse<Rating>(GetString(rating, "Rating"), out var r) ? r : Rating.Gray,
            Reasons = GetMessages(rating, "Reasons"),
            VulnerabilityCount = checkedForVulnerabilities || counted.Count > 0 ? counted.Count : null,
            PossibleCount = counted.Count(v => v.Assessment == "PossiblyAffected"),
            Vulnerabilities = vulnerabilities,
            Refuted = vulnerability is null ? [] : GetObjects(vulnerability, "Refuted").Select(r => MessageText(r.Properties["Note"]?.Value)).OfType<string>().ToList(),
            Sources = record is null ? "" : string.Join(", ", GetStrings(record, "Sources")),
            WingetId = record is null ? null : GetString(record, "WingetId"),
            CpeBase = vulnerability is null ? [] : GetStrings(vulnerability, "CpeBase"),
            CpeSource = vulnerability is null ? null : GetString(vulnerability, "CpeSource"),
            NeedsCpe = vulnerability?.Properties["Reason"]?.Value is PSObject reason && GetString(reason, "Code") == "NoCpe",
            InstallLocation = record is null ? null : GetString(record, "InstallLocation") ?? GetString(record, "FilePath"),
            InstallInfo = record is null ? null : InstallInfoText(record),
            Source = rating,
            CheckedAt = GetDate(rating, "CheckedAt"),
            UpdateCheckedAt = GetDate(rating, "UpdateCheckedAt"),
            VulnerabilityCheckedAt = GetDate(rating, "VulnerabilityCheckedAt"),
            CheckStale = rating.Properties["CheckStale"]?.Value is true,
        };
    }

    private static DateTime? GetDate(PSObject obj, string name) => obj.Properties[name]?.Value switch
    {
        PSObject { BaseObject: DateTime d } => d,
        DateTime d => d,
        DateTimeOffset o => o.UtcDateTime,
        _ => null,
    };

    private static string? InstallInfoText(PSObject record)
    {
        var scope = GetString(record, "Scope") switch
        {
            "Machine" => AppText.Get("ScopeMachine"),
            "User" => AppText.Get("ScopeUser"),
            _ => null,
        };
        var parts = new[] { GetString(record, "InstallType"), scope, GetString(record, "Architecture") }.Where(p => p is not null).ToList();
        return parts.Count == 0 ? null : string.Join(" · ", parts);
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

    internal static IEnumerable<PSObject> GetObjects(PSObject obj, string name) => obj.Properties[name]?.Value switch
    {
        null => [],
        string => [],
        IEnumerable list => list.Cast<object?>().Where(o => o is not null).Select(PSObject.AsPSObject!),
        var single => [PSObject.AsPSObject(single)],
    };

    /// <summary>Texte einer Liste von Meldungen (Code, Args, Text); ältere Daten enthalten reinen Text.</summary>
    private static IReadOnlyList<string> GetMessages(PSObject obj, string name) => obj.Properties[name]?.Value switch
    {
        null => [],
        string s => [s],
        IEnumerable list => list.Cast<object?>().Select(MessageText).OfType<string>().Where(s => s.Length > 0).ToList(),
        var single => MessageText(single) is { Length: > 0 } text ? [text] : [],
    };

    /// <summary>Text einer Meldung des Moduls; der Code bleibt im Modul, angezeigt wird nur Text.</summary>
    internal static string? MessageText(object? value) => value switch
    {
        null => null,
        string s => s,
        PSObject { BaseObject: string s } => s,
        PSObject ps when ps.Properties["Text"] is { } text => text.Value?.ToString(),
        PSObject ps => ps.BaseObject?.ToString(),
        var other => other.ToString(),
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
    /// <summary>Angabe jeder Quelle einzeln (NVD, CIRCL), auch wenn sie übereinstimmen.</summary>
    public IReadOnlyList<SourceStatementItem> Sources { get; init; } = [];

    public string AssessmentText => Assessment is null ? "" : AppText.Find("Assessment" + Assessment) ?? Assessment;

    /// <summary>Kurzinfo hinter der CVE-Nummer, z. B. „betroffen · aktiv ausgenutzt (KEV) · CVSS 7.0 · EPSS 67 %“.</summary>
    public string Summary => string.Join(" · ", new[]
    {
        AssessmentText,
        Kev ? AppText.Get("VulnerabilityKev") : null,
        Score is { } s ? $"CVSS {s.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture)}" : null,
        Epss is { } e ? "EPSS " + e.ToString("P0", System.Globalization.CultureInfo.CurrentCulture) : null,
    }.Where(p => !string.IsNullOrEmpty(p)));

    public static VulnerabilityItem FromPs(PSObject obj)
    {
        var url = obj.Properties["Url"]?.Value?.ToString();
        return new VulnerabilityItem(
            obj.Properties["CveId"]?.Value?.ToString() ?? "",
            obj.Properties["Assessment"]?.Value?.ToString(),
            SoftwareItem.MessageText(obj.Properties["Note"]?.Value),
            obj.Properties["Kev"]?.Value is true,
            Number(obj.Properties["Score"]?.Value),
            Number(obj.Properties["Epss"]?.Value),
            HttpsUri(url),
            obj.Properties["Description"]?.Value?.ToString())
        {
            Sources = SoftwareItem.GetObjects(obj, "Sources").Select(SourceStatementItem.FromPs).ToList(),
        };
    }

    internal static Uri? HttpsUri(string? url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps ? uri : null;

    private static double? Number(object? value) => value switch
    {
        null => null,
        PSObject ps => Number(ps.BaseObject),
        double d => d,
        IConvertible c => c.ToDouble(System.Globalization.CultureInfo.InvariantCulture),
        _ => null,
    };
}

/// <summary>Angabe einer Quelle zu einer Lücke: Urteil, Versionsbereich, Namensnennung (z. B. CC BY 4.0) und Link.</summary>
public sealed record SourceStatementItem(string Source, string Verdict, string? Range, string? Note, string? Attribution, Uri? Url)
{
    /// <summary>z. B. „CIRCL: betroffen (&lt; 24.09)“.</summary>
    public string Line
    {
        get
        {
            var verdict = AppText.Find("SourceVerdict" + Verdict) ?? Verdict;
            return Range is null
                ? AppText.Format("SourceStatementLine", Source, verdict)
                : AppText.Format("SourceStatementLineRange", Source, verdict, Range);
        }
    }

    public static SourceStatementItem FromPs(PSObject obj) => new(
        obj.Properties["Source"]?.Value?.ToString() ?? "",
        obj.Properties["Verdict"]?.Value?.ToString() ?? "",
        obj.Properties["Range"]?.Value?.ToString() is { Length: > 0 } range ? range : null,
        SoftwareItem.MessageText(obj.Properties["Note"]?.Value),
        SoftwareItem.MessageText(obj.Properties["Attribution"]?.Value),
        VulnerabilityItem.HttpsUri(obj.Properties["Url"]?.Value?.ToString()));
}
