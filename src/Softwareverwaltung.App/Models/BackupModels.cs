using System.Collections;
using System.Globalization;
using System.Management.Automation;
using Softwareverwaltung.App.Localization;

namespace Softwareverwaltung.App.Models;

/// <summary>
/// Abbild von SoftwareInventory.RegistryBackup (Get-RegistryBackup): eine Sicherung, die „Eintrag entfernen“
/// angelegt hat. Nur Anzeige; ob sie sich zurückspielen lässt, entscheidet das Modul (CanRestore).
/// </summary>
public sealed record RegistryBackupItem
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    /// <summary>Zeitpunkt der Sicherung in UTC.</summary>
    public DateTime? CreatedAt { get; init; }
    public string? NativeKey { get; init; }
    /// <summary>Ältere Sicherung ohne Begleitdatei: nur löschbar.</summary>
    public bool IsLegacy { get; init; }
    public bool CanRestore { get; init; }
    public string? ProblemCode { get; init; }
    /// <summary>Meldung des Moduls (UI-Sprache) zum Problem.</summary>
    public string? ProblemText { get; init; }
    /// <summary>Gründe aus der Begleitdatei als Meldungstexte des Moduls (z. B. „Neuere Installation daneben: …“).</summary>
    public IReadOnlyList<string> ReasonTexts { get; init; } = [];
    public PSObject? Source { get; init; }

    public string WhenText => CreatedAt is { } t
        ? DateTime.SpecifyKind(t, DateTimeKind.Utc).ToLocalTime().ToString("g", CultureInfo.CurrentCulture)
        : "";

    public string ReasonsText => IsLegacy ? AppText.Get("BackupsLegacyReason") : string.Join("; ", ReasonTexts);

    public string StatusText => CanRestore ? AppText.Get("BackupsRestorable") : ProblemText ?? ProblemCode ?? "";

    public static RegistryBackupItem FromPs(PSObject obj)
    {
        var reasons = new List<string>();
        var value = obj.Properties["Reasons"]?.Value;
        if ((value is PSObject p ? p.BaseObject : value) is IEnumerable list and not string)
        {
            foreach (var reason in list)
            {
                if (SoftwareItem.MessageText(reason) is { Length: > 0 } text)
                {
                    reasons.Add(text);
                }
            }
        }
        return new RegistryBackupItem
        {
            Id = ActionOutcome.Text(obj, "Id") ?? "",
            Name = ActionOutcome.Text(obj, "Name") ?? "",
            CreatedAt = Date(obj.Properties["CreatedAt"]?.Value),
            NativeKey = ActionOutcome.Text(obj, "NativeKey"),
            IsLegacy = obj.Properties["IsLegacy"]?.Value is true,
            CanRestore = obj.Properties["CanRestore"]?.Value is true,
            ProblemCode = ActionOutcome.Text(obj, "Problem"),
            ProblemText = SoftwareItem.MessageText(obj.Properties["ProblemMessage"]?.Value),
            ReasonTexts = reasons,
            Source = obj,
        };
    }

    private static DateTime? Date(object? value) => value switch
    {
        PSObject ps => Date(ps.BaseObject),
        DateTime d => d,
        DateTimeOffset o => o.UtcDateTime,
        string s when DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var d) => d,
        _ => null,
    };
}
