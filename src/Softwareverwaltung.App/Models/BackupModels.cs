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
    /// <summary>Bereich laut Modul (User, Machine), unübersetzt.</summary>
    public string? ScopeCode { get; init; }
    /// <summary>Zurückspielen und Löschen brauchen Administratorrechte (HKLM, über den Helfer).</summary>
    public bool Elevated { get; init; }
    /// <summary>Älter als 365 Tage.</summary>
    public bool Expired { get; init; }
    /// <summary>Der Eintrag existiert schon wieder (vom Modul ohne UAC gelesen); dann nicht zurückspielbar.</summary>
    public bool KeyPresent { get; init; }
    /// <summary>Zum selben Schlüssel gibt es eine neuere Sicherung.</summary>
    public bool NewerExists { get; init; }
    public PSObject? Source { get; init; }

    public string ScopeText => AppText.Get(ScopeCode == "Machine" ? "BackupsScopeMachine" : "BackupsScopeUser");

    public string WhenText => CreatedAt is { } t
        ? DateTime.SpecifyKind(t, DateTimeKind.Utc).ToLocalTime().ToString("g", CultureInfo.CurrentCulture)
        : "";

    public string ReasonsText => IsLegacy ? AppText.Get("BackupsLegacyReason") : string.Join("; ", ReasonTexts);

    public string StatusText
    {
        get
        {
            // Problem der Sicherung vor „Eintrag ist vorhanden“; Markierungen (älter als 365 Tage, ältere Sicherung) vorn.
            var text = CanRestore ? AppText.Get("BackupsRestorable")
                : ProblemText ?? ProblemCode ?? (KeyPresent ? AppText.Get("BackupsKeyPresent") : "");
            var marks = new List<string>();
            if (Expired)
            {
                marks.Add(AppText.Get("BackupsExpired"));
            }
            if (NewerExists)
            {
                marks.Add(AppText.Get("BackupsOlderBackup"));
            }
            if (text.Length > 0)
            {
                marks.Add(text);
            }
            return string.Join("; ", marks);
        }
    }

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
            ScopeCode = ActionOutcome.Text(obj, "Scope"),
            Elevated = obj.Properties["Elevated"]?.Value is true,
            Expired = obj.Properties["Expired"]?.Value is true,
            KeyPresent = obj.Properties["KeyPresent"]?.Value is true,
            NewerExists = obj.Properties["NewerExists"]?.Value is true,
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

/// <summary>Abbild von SoftwareInventory.RegistryBackupStatus (Get-RegistryBackupStatus): Zustand des Admin-Ordners.</summary>
public sealed record RegistryBackupStatus
{
    /// <summary>Missing, Readable oder Unreadable.</summary>
    public string MachineFolderState { get; init; } = "Missing";
    public string? MachineFolder { get; init; }
    public int ExpiredMachineCount { get; init; }

    public static RegistryBackupStatus FromPs(PSObject obj) => new()
    {
        MachineFolderState = ActionOutcome.Text(obj, "MachineFolderState") ?? "Missing",
        MachineFolder = ActionOutcome.Text(obj, "MachineFolder"),
        ExpiredMachineCount = obj.Properties["ExpiredMachineCount"]?.Value is int count ? count : 0,
    };
}
