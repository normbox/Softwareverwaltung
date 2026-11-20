using System.Management.Automation;
using Softwareverwaltung.App.Models;

namespace Softwareverwaltung.App.Services;

/// <summary>Liste der Registry-Sicherungen (Get-RegistryBackup). Zurückspielen und Löschen laufen über <see cref="IActionService"/>.</summary>
public interface IBackupService
{
    Task<IReadOnlyList<RegistryBackupItem>> GetBackupsAsync(CancellationToken cancellationToken = default);

    /// <summary>Zustand des Admin-Ordners für HKLM-Sicherungen (Get-RegistryBackupStatus), nur lesend.</summary>
    Task<RegistryBackupStatus> GetStatusAsync(CancellationToken cancellationToken = default);
}

public sealed class BackupService(IPowerShellHost host) : IBackupService
{
    public async Task<IReadOnlyList<RegistryBackupItem>> GetBackupsAsync(CancellationToken cancellationToken = default)
    {
        var result = await host.InvokeAsync(new PSCommand().AddCommand("Get-RegistryBackup"), cancellationToken: cancellationToken).ConfigureAwait(false);
        if (result.Errors.Count > 0)
        {
            throw new InvalidOperationException(string.Join(Environment.NewLine, result.Errors));
        }
        return result.Output.Select(RegistryBackupItem.FromPs).ToList();
    }

    public async Task<RegistryBackupStatus> GetStatusAsync(CancellationToken cancellationToken = default)
    {
        var result = await host.InvokeAsync(new PSCommand().AddCommand("Get-RegistryBackupStatus"), cancellationToken: cancellationToken).ConfigureAwait(false);
        if (result.Errors.Count > 0)
        {
            throw new InvalidOperationException(string.Join(Environment.NewLine, result.Errors));
        }
        return result.Output.Select(RegistryBackupStatus.FromPs).FirstOrDefault() ?? new RegistryBackupStatus();
    }
}
