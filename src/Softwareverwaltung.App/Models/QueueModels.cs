using System.Management.Automation;
using CommunityToolkit.Mvvm.ComponentModel;
using Softwareverwaltung.App.Localization;

namespace Softwareverwaltung.App.Models;

/// <summary>Häkchen einer Zeile für die Update-Warteschlange (eigenes Objekt, damit die Zeile selbst unverändert bleibt).</summary>
public sealed partial class QueueSelection : ObservableObject
{
    [ObservableProperty]
    private bool _isChecked;
}

/// <summary>Abbild von SoftwareInventory.UpdateQueueEntry: ein geplanter Eintrag mit genauem Befehl.</summary>
public sealed record QueueEntry(
    int Index, string Name, string? InstalledVersion, string? LatestVersion, bool Unconfirmed,
    bool Executable, bool Elevated, string? CommandLine, string? Reason, PSObject Source)
{
    public string VersionText => AppText.Format("QueueVersions", InstalledVersion ?? "?", LatestVersion ?? "?");

    public static QueueEntry FromPs(PSObject obj) => new(
        Convert.ToInt32(obj.Properties["Index"]?.Value ?? 0, System.Globalization.CultureInfo.InvariantCulture),
        ActionOutcome.Text(obj, "Name") ?? "",
        ActionOutcome.Text(obj, "InstalledVersion"),
        ActionOutcome.Text(obj, "LatestVersion"),
        obj.Properties["Unconfirmed"]?.Value is true,
        obj.Properties["Executable"]?.Value is true,
        obj.Properties["Elevated"]?.Value is true,
        ActionOutcome.Text(obj, "CommandLine"),
        SoftwareItem.MessageText(obj.Properties["Message"]?.Value),
        obj);
}

/// <summary>Gemeinsame Bestätigung: geplante Einträge in drei Gruppen.</summary>
public sealed class QueueConfirmation(IReadOnlyList<QueueEntry> entries)
{
    public IReadOnlyList<QueueEntry> Elevated { get; } = entries.Where(e => e.Executable && e.Elevated).ToList();
    public IReadOnlyList<QueueEntry> Normal { get; } = entries.Where(e => e.Executable && !e.Elevated).ToList();
    public IReadOnlyList<QueueEntry> NotExecutable { get; } = entries.Where(e => !e.Executable).ToList();
    public bool CanStart => Elevated.Count + Normal.Count > 0;
    public string SummaryText => AppText.Format("QueueConfirmSummary", Elevated.Count + Normal.Count, NotExecutable.Count);
}

/// <summary>Status eines Eintrags während die Warteschlange läuft (Codes aus dem Modul).</summary>
public sealed partial class QueueEntryState(int index, string name) : ObservableObject
{
    public int Index { get; } = index;
    public string Name { get; } = name;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(StatusText), nameof(IsDone))]
    private string _status = "Waiting";

    /// <summary>Grund bei Fehlschlag (Text der Meldung aus dem Modul), sonst leer.</summary>
    [ObservableProperty]
    private string? _message;

    public bool IsDone => Status is not ("Waiting" or "Running");

    public string StatusText => Status switch
    {
        "Waiting" => AppText.Get("QueueStatusWaiting"),
        "Running" => AppText.Get("QueueStatusRunning"),
        var code => AppText.Find("ActionResult" + code) ?? code,
    };
}
