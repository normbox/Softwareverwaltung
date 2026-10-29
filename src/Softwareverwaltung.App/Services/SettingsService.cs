using System.Management.Automation;
using System.Security;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Localization;

namespace Softwareverwaltung.App.Services;

public interface ISettingsService
{
    Task<AppSettings> LoadAsync(CancellationToken cancellationToken = default);

    Task<AppSettings> SaveAsync(AppSettings settings, CancellationToken cancellationToken = default);

    /// <summary>Speichert nur Privat/Firma, andere ungespeicherte Änderungen bleiben unberührt.</summary>
    Task<AppSettings> SaveUsageAsync(string usage, CancellationToken cancellationToken = default);

    Task<SettingPreset> GetPresetAsync(string preset, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<ScanDrive>> GetDrivesAsync(CancellationToken cancellationToken = default);

    /// <summary>Hinweise zu den Nutzungsbedingungen der Dienste für Privat oder Firma. Ändert nichts.</summary>
    Task<IReadOnlyList<ServiceTermsNotice>> GetServiceTermsAsync(string usage, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<CredentialStatus>> GetCredentialStatusAsync(CancellationToken cancellationToken = default);

    Task<CredentialStatus> SetCredentialAsync(string service, SecureString secret, CancellationToken cancellationToken = default);

    Task<CredentialStatus> RemoveCredentialAsync(string service, CancellationToken cancellationToken = default);
}

/// <summary>Einstellungen und API-Schlüssel über die Modulfunktionen. Fehler des Moduls werden zu Ausnahmen.</summary>
public sealed class SettingsService(IPowerShellHost host) : ISettingsService
{
    public async Task<AppSettings> LoadAsync(CancellationToken cancellationToken = default) =>
        AppSettings.FromPs(await InvokeSingleAsync(new PSCommand().AddCommand("Get-InventorySetting"), cancellationToken).ConfigureAwait(false));

    public async Task<AppSettings> SaveAsync(AppSettings settings, CancellationToken cancellationToken = default)
    {
        var command = new PSCommand().AddCommand("Set-InventorySetting")
            .AddParameter("Enable", settings.Switches.Where(s => s.Value).Select(s => s.Key).ToArray())
            .AddParameter("Disable", settings.Switches.Where(s => !s.Value).Select(s => s.Key).ToArray())
            .AddParameter("ScanMode", settings.ScanMode ?? "None")
            .AddParameter("ScanPath", settings.ScanPaths.ToArray())
            .AddParameter("ScanDrive", settings.ScanDrives.ToArray())
            .AddParameter("ExcludePath", settings.ExcludePaths.ToArray())
            .AddParameter("IncludeTemp", settings.IncludeTemp)
            .AddParameter("ComputeHash", settings.ComputeHash)
            .AddParameter("SmartExclusions", settings.SmartExclusions)
            .AddParameter("PortableSearch", settings.PortableSearch)
            .AddParameter("TraceSearch", settings.TraceSearch)
            .AddParameter("FileSearch", settings.FileSearch)
            .AddParameter("LogRetentionDays", settings.LogRetentionDays)
            .AddParameter("LogMaxSizeMB", settings.LogMaxSizeMB)
            .AddParameter("CacheHoursLatestVersion", settings.CacheHoursLatestVersion)
            .AddParameter("CacheHoursNvd", settings.CacheHoursNvd)
            .AddParameter("CacheHoursCircl", settings.CacheHoursCircl)
            .AddParameter("CacheHoursEpss", settings.CacheHoursEpss)
            .AddParameter("CacheHoursKev", settings.CacheHoursKev);
        if (settings.Usage is not null)
        {
            command.AddParameter("Usage", settings.Usage);
        }
        return AppSettings.FromPs(await InvokeSingleAsync(command, cancellationToken).ConfigureAwait(false));
    }

    public async Task<AppSettings> SaveUsageAsync(string usage, CancellationToken cancellationToken = default) =>
        AppSettings.FromPs(await InvokeSingleAsync(new PSCommand().AddCommand("Set-InventorySetting").AddParameter("Usage", usage), cancellationToken).ConfigureAwait(false));

    public async Task<SettingPreset> GetPresetAsync(string preset, CancellationToken cancellationToken = default) =>
        SettingPreset.FromPs(await InvokeSingleAsync(new PSCommand().AddCommand("Get-SettingPreset").AddParameter("Preset", preset), cancellationToken).ConfigureAwait(false));

    public async Task<IReadOnlyList<ScanDrive>> GetDrivesAsync(CancellationToken cancellationToken = default) =>
        (await InvokeAsync(new PSCommand().AddCommand("Get-ScanDrive"), cancellationToken).ConfigureAwait(false)).Select(ScanDrive.FromPs).ToList();

    public async Task<IReadOnlyList<ServiceTermsNotice>> GetServiceTermsAsync(string usage, CancellationToken cancellationToken = default) =>
        (await InvokeAsync(new PSCommand().AddCommand("Get-ServiceTermsNotice").AddParameter("Usage", usage), cancellationToken).ConfigureAwait(false)).Select(ServiceTermsNotice.FromPs).ToList();

    public async Task<IReadOnlyList<CredentialStatus>> GetCredentialStatusAsync(CancellationToken cancellationToken = default) =>
        (await InvokeAsync(new PSCommand().AddCommand("Get-ServiceCredentialStatus"), cancellationToken).ConfigureAwait(false)).Select(CredentialStatus.FromPs).ToList();

    public async Task<CredentialStatus> SetCredentialAsync(string service, SecureString secret, CancellationToken cancellationToken = default) =>
        CredentialStatus.FromPs(await InvokeSingleAsync(
            new PSCommand().AddCommand("Set-ServiceCredential").AddParameter("Service", service).AddParameter("Secret", secret), cancellationToken).ConfigureAwait(false));

    public async Task<CredentialStatus> RemoveCredentialAsync(string service, CancellationToken cancellationToken = default) =>
        CredentialStatus.FromPs(await InvokeSingleAsync(
            new PSCommand().AddCommand("Remove-ServiceCredential").AddParameter("Service", service), cancellationToken).ConfigureAwait(false));

    private async Task<IReadOnlyList<PSObject>> InvokeAsync(PSCommand command, CancellationToken cancellationToken)
    {
        var result = await host.InvokeAsync(command, cancellationToken: cancellationToken).ConfigureAwait(false);
        if (result.Errors.Count > 0)
        {
            throw new InvalidOperationException(string.Join(Environment.NewLine, result.Errors));
        }
        return result.Output;
    }

    private async Task<PSObject> InvokeSingleAsync(PSCommand command, CancellationToken cancellationToken) =>
        (await InvokeAsync(command, cancellationToken).ConfigureAwait(false)).FirstOrDefault()
        ?? throw new InvalidOperationException(AppText.Get("ErrorModuleNoResult"));
}
