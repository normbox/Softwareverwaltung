using System.Management.Automation;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Localization;

namespace Softwareverwaltung.App.Services;

public interface IActionService
{
    /// <summary>Fragt das Modul mit -WhatIf, was ausgeführt würde. Führt nichts aus.</summary>
    Task<ActionOutcome> PlanAsync(SoftwareActionKind kind, PSObject? source, string method = "Auto", CancellationToken cancellationToken = default);

    /// <summary>Führt genau den bestätigten Plan aus; weicht der Befehl ab, führt das Modul nichts aus.</summary>
    Task<ActionOutcome> ExecuteAsync(SoftwareActionKind kind, PSObject? source, ActionOutcome confirmedPlan, string method = "Auto", CancellationToken cancellationToken = default);

    /// <summary>Liest das Programm nach einer Aktion neu ein; null, wenn es nicht mehr installiert ist.</summary>
    Task<SoftwareItem?> RecheckAsync(PSObject source, CancellationToken cancellationToken = default, bool refresh = false);

    /// <summary>Verwirft die zwischengespeicherten Online-Ergebnisse eines Programms (Clear-CheckCache).</summary>
    Task ClearCheckCacheAsync(PSObject source, CancellationToken cancellationToken = default);

    /// <summary>Plant die Update-Warteschlange ohne Ausführung (Get-UpdateQueuePlan).</summary>
    Task<IReadOnlyList<QueueEntry>> PlanUpdateQueueAsync(IReadOnlyList<PSObject> sources, IProgress<string>? progress = null, CancellationToken cancellationToken = default);

    /// <summary>
    /// Führt die bestätigten Einträge aus (Invoke-UpdateQueue). <paramref name="control"/> ist eine
    /// synchronisierte Hashtabelle: State (Running/Paused/Cancelled) setzt die App, Status liest sie.
    /// </summary>
    Task<IReadOnlyList<ActionOutcome>> RunUpdateQueueAsync(IReadOnlyList<QueueEntry> entries, System.Collections.Hashtable control, IProgress<string>? progress = null);

    Task<IReadOnlyList<ActionHistoryEntry>> GetHistoryAsync(string name, CancellationToken cancellationToken = default);
}

/// <summary>Aktualisieren, Deinstallieren und winget installieren über die Modulfunktionen.</summary>
public sealed class ActionService(IPowerShellHost host) : IActionService
{
    public async Task<ActionOutcome> PlanAsync(SoftwareActionKind kind, PSObject? source, string method = "Auto", CancellationToken cancellationToken = default)
    {
        var command = NewCommand(kind, source, method).AddParameter("WhatIf");
        return await InvokeOutcomeAsync(command, cancellationToken).ConfigureAwait(false);
    }

    public async Task<ActionOutcome> ExecuteAsync(SoftwareActionKind kind, PSObject? source, ActionOutcome confirmedPlan, string method = "Auto", CancellationToken cancellationToken = default)
    {
        var command = NewCommand(kind, source, method).AddParameter("Confirm", false);
        if (kind != SoftwareActionKind.InstallWinget)
        {
            // Wiederherstellungspunkt wie im Dialog gezeigt, nicht wie die Einstellung inzwischen lautet.
            command.AddParameter("CreateRestorePoint", new SwitchParameter(confirmedPlan.RestorePointPlanned));
            if (confirmedPlan.CommandLine is not null)
            {
                command.AddParameter("ConfirmedCommandLine", confirmedPlan.CommandLine);
            }
        }
        return await InvokeOutcomeAsync(command, cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<QueueEntry>> PlanUpdateQueueAsync(IReadOnlyList<PSObject> sources, IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        var command = new PSCommand().AddCommand("Get-UpdateQueuePlan").AddParameter("InputObject", sources.ToArray());
        var result = await host.InvokeAsync(command, progress, cancellationToken).ConfigureAwait(false);
        if (result.Errors.Count > 0)
        {
            throw new InvalidOperationException(string.Join(Environment.NewLine, result.Errors));
        }
        return result.Output.Select(QueueEntry.FromPs).ToList();
    }

    public async Task<IReadOnlyList<ActionOutcome>> RunUpdateQueueAsync(IReadOnlyList<QueueEntry> entries, System.Collections.Hashtable control, IProgress<string>? progress = null)
    {
        var command = new PSCommand().AddCommand("Invoke-UpdateQueue")
            .AddParameter("Entry", entries.Select(e => e.Source).ToArray())
            .AddParameter("Control", control);
        var result = await host.InvokeAsync(command, progress).ConfigureAwait(false);
        return result.Output.Select(ActionOutcome.FromPs).ToList();
    }

    public async Task ClearCheckCacheAsync(PSObject source, CancellationToken cancellationToken = default)
    {
        var command = new PSCommand().AddCommand("Clear-CheckCache").AddParameter("InputObject", source).AddParameter("Confirm", false);
        await host.InvokeAsync(command, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    public async Task<SoftwareItem?> RecheckAsync(PSObject source, CancellationToken cancellationToken = default, bool refresh = false)
    {
        var command = new PSCommand().AddCommand("Find-InstalledSoftware").AddParameter("Reference", source).AddCommand("Get-SecurityRating");
        if (refresh)
        {
            command.AddParameter("Refresh");
        }
        var result = await host.InvokeAsync(command, cancellationToken: cancellationToken).ConfigureAwait(false);
        if (result.Errors.Count > 0)
        {
            throw new InvalidOperationException(string.Join(Environment.NewLine, result.Errors));
        }
        return result.Output.Select(SoftwareItem.FromRating).FirstOrDefault();
    }

    public async Task<IReadOnlyList<ActionHistoryEntry>> GetHistoryAsync(string name, CancellationToken cancellationToken = default)
    {
        var command = new PSCommand().AddCommand("Get-ActionLog").AddParameter("Name", WildcardPattern.Escape(name));
        var result = await host.InvokeAsync(command, cancellationToken: cancellationToken).ConfigureAwait(false);
        return result.Output.Select(ActionHistoryEntry.FromPs).OrderByDescending(e => e.StartedAt).ToList();
    }

    private static PSCommand NewCommand(SoftwareActionKind kind, PSObject? source, string method)
    {
        var command = new PSCommand();
        switch (kind)
        {
            case SoftwareActionKind.Update:
                command.AddCommand("Update-Software").AddParameter("InputObject", Required(source));
                break;
            case SoftwareActionKind.Uninstall:
                command.AddCommand("Uninstall-Software").AddParameter("InputObject", Required(source)).AddParameter("Method", method);
                break;
            default:
                command.AddCommand("Install-WingetPackageManager");
                break;
        }
        return command;
    }

    private static PSObject Required(PSObject? source) =>
        source ?? throw new InvalidOperationException(AppText.Get("ErrorItemWithoutModuleData"));

    private async Task<ActionOutcome> InvokeOutcomeAsync(PSCommand command, CancellationToken cancellationToken)
    {
        var result = await host.InvokeAsync(command, cancellationToken: cancellationToken).ConfigureAwait(false);
        var outcome = result.Output.FirstOrDefault();
        if (outcome is null)
        {
            throw new InvalidOperationException(result.Errors.Count > 0
                ? string.Join(Environment.NewLine, result.Errors)
                : AppText.Get("ErrorModuleNoResult"));
        }
        return ActionOutcome.FromPs(outcome);
    }
}
