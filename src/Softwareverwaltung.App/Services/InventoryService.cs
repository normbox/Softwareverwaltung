using System.Management.Automation;
using Softwareverwaltung.App.Models;

namespace Softwareverwaltung.App.Services;

public sealed record WingetStatus(bool Available, string? Message, Uri? InstallUrl);

public sealed record ScanResult(IReadOnlyList<SoftwareItem> Items, IReadOnlyList<string> Warnings, IReadOnlyList<string> Errors);

public interface IInventoryService
{
    Task<IReadOnlyList<string>> InitializeAsync(CancellationToken cancellationToken = default);

    Task<WingetStatus> GetWingetStatusAsync(CancellationToken cancellationToken = default);

    Task<ScanResult> ScanAsync(IProgress<string>? progress = null, CancellationToken cancellationToken = default);
}

/// <summary>Ruft die Modulfunktionen auf und bildet die Ergebnisse auf Modelle ab.</summary>
public sealed class InventoryService(IPowerShellHost host) : IInventoryService
{
    public async Task<IReadOnlyList<string>> InitializeAsync(CancellationToken cancellationToken = default)
    {
        await host.InitializeAsync(cancellationToken).ConfigureAwait(false);
        return host.StartupMessages;
    }

    public async Task<WingetStatus> GetWingetStatusAsync(CancellationToken cancellationToken = default)
    {
        var result = await host.InvokeAsync(new PSCommand().AddCommand("Test-WingetAvailability"), cancellationToken: cancellationToken).ConfigureAwait(false);
        var status = result.Output.FirstOrDefault();
        if (status is null)
        {
            return new WingetStatus(false, "winget-Status nicht ermittelbar: " + string.Join(" ", result.Errors), null);
        }
        var url = status.Properties["InstallUrl"]?.Value?.ToString();
        return new WingetStatus(
            status.Properties["Available"]?.Value is true,
            status.Properties["Message"]?.Value?.ToString(),
            Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps ? uri : null);
    }

    public async Task<ScanResult> ScanAsync(IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        // Wie im Modul dokumentiert: installierte und (falls eingerichtet) portable Programme, dann Ampel mit den aktivierten Diensten.
        var command = new PSCommand().AddCommand("Invoke-InventoryScan").AddCommand("Get-SecurityRating");
        var result = await host.InvokeAsync(command, progress, cancellationToken).ConfigureAwait(false);
        var items = result.Output.Select(SoftwareItem.FromRating).ToList();
        return new ScanResult(items, result.Warnings.Distinct().ToList(), result.Errors);
    }
}
