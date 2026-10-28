using System.Management.Automation;
using Softwareverwaltung.App.Localization;
using Softwareverwaltung.App.Models;

namespace Softwareverwaltung.App.Services;

/// <summary>CPE-Zuordnungen über das Modul: Vorschläge, bestätigen, entfernen, „Vorschlag melden“.</summary>
public interface ICpeService
{
    /// <summary>Unbestätigte Vorschläge (Find-CpeCandidate); ohne NVD kommt ein Hinweis statt Vorschlägen.</summary>
    Task<CpeSearchResult> FindCandidatesAsync(PSObject source, CancellationToken cancellationToken = default);

    /// <summary>Speichert die vom Benutzer bestätigte Zuordnung (Set-CpeMapping).</summary>
    Task SetMappingAsync(PSObject source, string cpe, CancellationToken cancellationToken = default);

    /// <summary>Entfernt die bestätigte Zuordnung (Remove-CpeMapping).</summary>
    Task RemoveMappingAsync(PSObject source, CancellationToken cancellationToken = default);

    /// <summary>Link zum vorausgefüllten GitHub-Issue (Get-CpeMappingReport); es wird nichts gesendet.</summary>
    Task<CpeReport> GetReportAsync(PSObject source, CancellationToken cancellationToken = default);
}

public sealed class CpeService(IPowerShellHost host) : ICpeService
{
    public async Task<CpeSearchResult> FindCandidatesAsync(PSObject source, CancellationToken cancellationToken = default)
    {
        var command = new PSCommand().AddCommand("Find-CpeCandidate").AddParameter("InputObject", source).AddParameter("First", 5);
        var result = await host.InvokeAsync(command, cancellationToken: cancellationToken).ConfigureAwait(false);
        var candidates = result.Output.Select(CpeCandidate.FromPs).Where(c => c.Cpe.Length > 0).ToList();
        var hint = result.Errors.Concat(result.Warnings).FirstOrDefault();
        return new CpeSearchResult(candidates, candidates.Count == 0 ? hint ?? AppText.Get("CpeNoCandidates") : null);
    }

    public Task SetMappingAsync(PSObject source, string cpe, CancellationToken cancellationToken = default) =>
        RunAsync(new PSCommand().AddCommand("Set-CpeMapping").AddParameter("InputObject", source).AddParameter("Cpe", new[] { cpe.Trim() }).AddParameter("Confirm", false), cancellationToken);

    public Task RemoveMappingAsync(PSObject source, CancellationToken cancellationToken = default) =>
        RunAsync(new PSCommand().AddCommand("Remove-CpeMapping").AddParameter("InputObject", source).AddParameter("Confirm", false), cancellationToken);

    public async Task<CpeReport> GetReportAsync(PSObject source, CancellationToken cancellationToken = default)
    {
        var result = await host.InvokeAsync(new PSCommand().AddCommand("Get-CpeMappingReport").AddParameter("InputObject", source), cancellationToken: cancellationToken).ConfigureAwait(false);
        if (result.Errors.Count > 0 || result.Output.FirstOrDefault() is not { } report)
        {
            throw new InvalidOperationException(result.Errors.Count > 0 ? string.Join(Environment.NewLine, result.Errors) : AppText.Get("ErrorModuleNoResult"));
        }
        // Nur Links ins eigene Repository öffnen
        var url = ActionOutcome.Text(report, "Url");
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps || uri.Host != "github.com")
        {
            throw new InvalidOperationException(AppText.Get("ErrorModuleNoResult"));
        }
        var fields = report.Properties["Fields"]?.Value is PSObject f ? f : null;
        var summary = fields is null ? "" : string.Join(Environment.NewLine,
            fields.Properties.Where(p => p.Value is not null && p.Value.ToString()!.Length > 0).Select(p => $"{p.Name}: {p.Value}"));
        return new CpeReport(ActionOutcome.Text(report, "Title") ?? "", uri, summary);
    }

    private async Task RunAsync(PSCommand command, CancellationToken cancellationToken)
    {
        var result = await host.InvokeAsync(command, cancellationToken: cancellationToken).ConfigureAwait(false);
        if (result.Errors.Count > 0)
        {
            throw new InvalidOperationException(string.Join(Environment.NewLine, result.Errors));
        }
    }
}
