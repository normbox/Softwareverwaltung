using System.Management.Automation;

namespace Softwareverwaltung.App.Models;

public enum SoftwareActionKind
{
    Update,
    Uninstall,
    InstallWinget,
}

/// <summary>
/// Abbild von SoftwareInventory.ActionResult: bei -WhatIf der Plan (Result „Planned“),
/// nach der Ausführung das Ergebnis. Keine eigene Bewertung, nur Anzeige.
/// </summary>
public sealed record ActionOutcome
{
    public required string Action { get; init; }
    public required string Name { get; init; }
    public string? Method { get; init; }
    public string? CommandLine { get; init; }
    public bool Elevated { get; init; }
    public required string Result { get; init; }
    public string? Message { get; init; }
    public string? RestorePoint { get; init; }
    public string? RestorePointMessage { get; init; }
    public string? NextMethod { get; init; }
    public Uri? VendorUrl { get; init; }
    public string? ExitCodeHex { get; init; }
    public string? Output { get; init; }

    public bool IsPlanned => Result == "Planned";
    public bool RestorePointPlanned => RestorePoint == "Planned";
    public bool IsSuccess => Result is "Succeeded" or "SucceededRebootRequired";

    public string ActionText => Action switch
    {
        "Update" => "Aktualisieren",
        "Uninstall" => "Deinstallieren",
        "InstallWinget" => "winget installieren",
        _ => Action,
    };

    public string ResultText => Result switch
    {
        "Planned" => "Geplant",
        "Succeeded" => "Erfolgreich",
        "SucceededRebootRequired" => "Erfolgreich, Neustart nötig",
        "NotVerified" => "Nicht bestätigt: Der Zustand hat sich nicht geändert",
        "Cancelled" => "Abgebrochen",
        "ElevationDenied" => "Administratorrechte abgelehnt",
        "NotInstalled" => "Nicht (mehr) installiert",
        "NoUpdateAvailable" => "Kein Update verfügbar",
        "ManualUpdateRequired" => "Update von Hand nötig",
        "Unsupported" => "Nicht ausführbar",
        "Timeout" => "Keine Rückmeldung (Zeitüberschreitung)",
        "Failed" => "Fehlgeschlagen",
        _ => Result,
    };

    public string RightsText => Elevated
        ? "Mit Administratorrechten – Windows fragt gleich nach (UAC)."
        : "Ohne Administratorrechte.";

    public string RestorePointText => RestorePoint switch
    {
        "Planned" => "Vorher wird ein Wiederherstellungspunkt angelegt (eigene Windows-Abfrage möglich).",
        "Created" => "Wiederherstellungspunkt angelegt.",
        "Skipped" => "Kein neuer Wiederherstellungspunkt (Windows legt höchstens einen pro Tag an).",
        "NotAvailable" => "Wiederherstellungspunkt nicht verfügbar" + (RestorePointMessage is null ? "." : $": {RestorePointMessage}"),
        "Failed" => "Wiederherstellungspunkt fehlgeschlagen" + (RestorePointMessage is null ? "." : $": {RestorePointMessage}"),
        _ => "Kein Wiederherstellungspunkt (in den Einstellungen einschaltbar).",
    };

    public static ActionOutcome FromPs(PSObject obj)
    {
        var url = Text(obj, "VendorUrl");
        return new ActionOutcome
        {
            Action = Text(obj, "Action") ?? "",
            Name = Text(obj, "Name") ?? "",
            Method = Text(obj, "Method"),
            CommandLine = Text(obj, "CommandLine"),
            Elevated = obj.Properties["Elevated"]?.Value is true,
            Result = Text(obj, "Result") ?? "Failed",
            Message = Text(obj, "Message"),
            RestorePoint = Text(obj, "RestorePoint"),
            RestorePointMessage = Text(obj, "RestorePointMessage"),
            NextMethod = Text(obj, "NextMethod"),
            VendorUrl = Uri.TryCreate(url, UriKind.Absolute, out var uri) && (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp) ? uri : null,
            ExitCodeHex = Text(obj, "ExitCodeHex"),
            Output = Text(obj, "Output"),
        };
    }

    internal static string? Text(PSObject obj, string name)
    {
        var value = obj.Properties[name]?.Value;
        var text = value is PSObject ps ? ps.BaseObject?.ToString() : value?.ToString();
        return string.IsNullOrWhiteSpace(text) ? null : text;
    }
}

/// <summary>Eine frühere Aktion zu einem Programm aus Get-ActionLog.</summary>
public sealed record ActionHistoryEntry(DateTime? StartedAt, string Action, string? Method, string Result, string? Message)
{
    public string Text
    {
        get
        {
            var outcome = new ActionOutcome { Action = Action, Name = "", Result = Result };
            var when = StartedAt is { } t ? t.ToLocalTime().ToString("dd.MM.yyyy HH:mm") : "?";
            return $"{when} · {outcome.ActionText}{(Method is null ? "" : $" über {Method}")} · {outcome.ResultText}";
        }
    }

    public static ActionHistoryEntry FromPs(PSObject obj) => new(
        Date(obj.Properties["StartedAt"]?.Value),
        ActionOutcome.Text(obj, "Action") ?? "",
        ActionOutcome.Text(obj, "Method"),
        ActionOutcome.Text(obj, "Result") ?? "",
        ActionOutcome.Text(obj, "Message"));

    private static DateTime? Date(object? value) => value switch
    {
        PSObject ps => Date(ps.BaseObject),
        DateTime d => d,
        DateTimeOffset o => o.UtcDateTime,
        string s when DateTime.TryParse(s, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var d) => d,
        _ => null,
    };
}
