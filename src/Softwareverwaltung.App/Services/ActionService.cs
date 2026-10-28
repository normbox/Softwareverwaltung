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
    Task<SoftwareItem?> RecheckAsync(PSObject source, CancellationToken cancellationToken = default);

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

    public async Task<SoftwareItem?> RecheckAsync(PSObject source, CancellationToken cancellationToken = default)
    {
        var command = new PSCommand().AddCommand("Find-InstalledSoftware").AddParameter("Reference", source).AddCommand("Get-SecurityRating");
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
