using System.Management.Automation;
using Softwareverwaltung.App.Localization;

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
    /// <summary>Store-Paket (Quelle „msstore“) ohne bestätigte Store-Vereinbarung: erst zustimmen lassen.</summary>
    public bool IsStoreAgreementRequired => Result == "StoreAgreementRequired";

    // Texte über Codes: Schlüssel = Präfix + Code aus dem Modul (z. B. ActionResultFailed).
    public string ActionText => AppText.Find("Action" + Action) ?? Action;

    public string ResultText => AppText.Find("ActionResult" + Result) ?? Result;

    public string RightsText => AppText.Get(Elevated ? "ActionRightsElevated" : "ActionRightsNormal");

    public string? RetryText => NextMethod is null ? null : AppText.Format("ActionRetryWith", NextMethod);

    public string RestorePointText => RestorePoint switch
    {
        "Planned" or "Created" or "Skipped" => AppText.Get("RestorePoint" + RestorePoint),
        "NotAvailable" or "Failed" => RestorePointMessage is null
            ? AppText.Get("RestorePoint" + RestorePoint)
            : AppText.Format("RestorePoint" + RestorePoint + "WithMessage", RestorePointMessage),
        _ => AppText.Get("RestorePointNone"),
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
            Message = SoftwareItem.MessageText(obj.Properties["Message"]?.Value),
            RestorePoint = Text(obj, "RestorePoint"),
            RestorePointMessage = SoftwareItem.MessageText(obj.Properties["RestorePointMessage"]?.Value),
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
            var when = StartedAt is { } t ? t.ToLocalTime().ToString("g", System.Globalization.CultureInfo.CurrentCulture) : "?";
            return Method is null
                ? AppText.Format("ActionHistoryEntry", when, outcome.ActionText, outcome.ResultText)
                : AppText.Format("ActionHistoryEntryWithMethod", when, outcome.ActionText, Method, outcome.ResultText);
        }
    }

    public static ActionHistoryEntry FromPs(PSObject obj) => new(
        Date(obj.Properties["StartedAt"]?.Value),
        ActionOutcome.Text(obj, "Action") ?? "",
        ActionOutcome.Text(obj, "Method"),
        ActionOutcome.Text(obj, "Result") ?? "",
        SoftwareItem.MessageText(obj.Properties["Message"]?.Value));

    private static DateTime? Date(object? value) => value switch
    {
        PSObject ps => Date(ps.BaseObject),
        DateTime d => d,
        DateTimeOffset o => o.UtcDateTime,
        string s when DateTime.TryParse(s, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var d) => d,
        _ => null,
    };
}
