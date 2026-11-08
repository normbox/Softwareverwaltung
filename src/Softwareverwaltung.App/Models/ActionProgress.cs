using Softwareverwaltung.App.Localization;

namespace Softwareverwaltung.App.Models;

/// <summary>Texte zum Stand einer laufenden Aktion aus den Codes des Moduls (Phase, CancelResult).</summary>
public static class ActionProgress
{
    public const string WaitingForElevation = "WaitingForElevation";
    public const string WaitingForInstaller = "WaitingForInstaller";

    /// <summary>Ab dieser Wartezeit auf die UAC-Abfrage erscheint der deutliche Hinweis. Eine harte Grenze gibt es nicht.</summary>
    public static readonly TimeSpan HintAfter = TimeSpan.FromSeconds(30);

    /// <summary>Der Abbruch hat die Aktion nicht gestoppt: Der Installer läuft weiter.</summary>
    public static bool Continues(string? cancelResult) => cancelResult is "Continuing" or "Orphaned";

    public static string Clock(TimeSpan time) => $"{(int)time.TotalMinutes}:{time.Seconds:00}";

    public static string StatusText(string actionText, string name, string? phase, string? cancelResult, bool cancelRequested, TimeSpan waited)
    {
        if (cancelRequested)
        {
            return phase == WaitingForElevation ? AppText.Get("StatusActionCancelWhileUac")
                : Continues(cancelResult) ? AppText.Get("StatusActionContinues")
                : AppText.Get("StatusActionCancelling");
        }
        return phase switch
        {
            WaitingForElevation => AppText.Format("StatusActionWaitingUac", actionText, name, Clock(waited)),
            WaitingForInstaller => AppText.Get("StatusActionWaitingInstaller"),
            _ => AppText.Format("StatusActionRunning", actionText, name),
        };
    }

    public static string? ElevationHint(string? phase, TimeSpan waited) =>
        phase == WaitingForElevation && waited >= HintAfter ? AppText.Format("ActionElevationHint", Clock(waited)) : null;
}
