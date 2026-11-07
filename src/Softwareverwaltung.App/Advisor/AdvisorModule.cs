using System.Management.Automation;
using System.Text.Json;
using Softwareverwaltung.App.Localization;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;

namespace Softwareverwaltung.App.Advisor;

/// <summary>Ergebnis von Get-AdvisorEndpointCheck. Message ist der Text in der UI-Sprache (bei http im privaten Netz der Hinweis).</summary>
public sealed record AdvisorEndpointStatus(bool Ok, string Network, bool Unencrypted, string? Code, string? Message);

/// <summary>Die Modulfunktionen, die der Berater braucht. Eigene Schnittstelle, damit Tests sie vorgeben können.</summary>
public interface IAdvisorModule
{
    Task<AdvisorConnection> GetConnectionAsync(CancellationToken cancellationToken = default);

    Task<string> GetSystemPromptAsync(CancellationToken cancellationToken = default);

    /// <summary>Tools für die Freigabestufe dieser Anbieterart (auf Stufe 0 nur die Übersicht).</summary>
    Task<IReadOnlyList<AdvisorToolDefinition>> GetToolsAsync(AdvisorProviderKind kind, CancellationToken cancellationToken = default);

    /// <summary>Führt ein Tool aus; die Stufe bestimmt das Modul aus der Anbieterart.</summary>
    Task<AdvisorToolResult> InvokeToolAsync(string name, string argumentsJson, AdvisorProviderKind kind, CancellationToken cancellationToken = default);

    /// <summary>Bereinigt Text des Benutzers vor dem Senden (Protect-AdvisorText).</summary>
    Task<string> ProtectTextAsync(string text, CancellationToken cancellationToken = default);

    Task<AdvisorEndpointStatus> CheckEndpointAsync(string endpoint, CancellationToken cancellationToken = default);
}

/// <summary>Ruft die Beraterfunktionen des Moduls über die eingebettete PowerShell auf.</summary>
public sealed class AdvisorModule(IPowerShellHost host) : IAdvisorModule
{
    public async Task<AdvisorConnection> GetConnectionAsync(CancellationToken cancellationToken = default) =>
        AdvisorConnection.FromPs(await InvokeSingleAsync(new PSCommand().AddCommand("Get-AdvisorConnection"), cancellationToken).ConfigureAwait(false));

    public async Task<string> GetSystemPromptAsync(CancellationToken cancellationToken = default) =>
        (await InvokeSingleAsync(new PSCommand().AddCommand("Get-AdvisorTool").AddParameter("SystemPrompt"), cancellationToken).ConfigureAwait(false)).BaseObject.ToString() ?? "";

    public async Task<IReadOnlyList<AdvisorToolDefinition>> GetToolsAsync(AdvisorProviderKind kind, CancellationToken cancellationToken = default) =>
        (await InvokeAsync(new PSCommand().AddCommand("Get-AdvisorTool").AddParameter("ProviderKind", kind.ToString()), cancellationToken).ConfigureAwait(false))
            .Select(AdvisorToolDefinition.FromPs).Where(t => t.Name.Length > 0).ToList();

    public async Task<AdvisorToolResult> InvokeToolAsync(string name, string argumentsJson, AdvisorProviderKind kind, CancellationToken cancellationToken = default)
    {
        var command = new PSCommand().AddCommand("Invoke-AdvisorTool")
            .AddParameter("Name", name).AddParameter("ArgumentsJson", argumentsJson).AddParameter("ProviderKind", kind.ToString());
        var result = await host.InvokeAsync(command, cancellationToken: cancellationToken).ConfigureAwait(false);
        if (result.Errors.Count > 0 || result.Output.FirstOrDefault() is not { } output)
        {
            // Fehlertexte der Engine können Pfade enthalten: an das Modell geht nur der Code.
            ErrorLog.Write("AdvisorTool", new InvalidOperationException(string.Join(Environment.NewLine, result.Errors)));
            return new AdvisorToolResult(name, false, "ToolFailed", JsonSerializer.Serialize(new { error_code = "ToolFailed" }), null);
        }
        return new AdvisorToolResult(
            ActionOutcome.Text(output, "Name") ?? name,
            output.Properties["Ok"]?.Value is true,
            ActionOutcome.Text(output, "Code"),
            ActionOutcome.Text(output, "Content") ?? "{}",
            output.Properties["Proposal"]?.Value as PSObject);
    }

    public async Task<string> ProtectTextAsync(string text, CancellationToken cancellationToken = default) =>
        (await InvokeSingleAsync(new PSCommand().AddCommand("Protect-AdvisorText").AddParameter("Text", text), cancellationToken).ConfigureAwait(false)).BaseObject.ToString() ?? "";

    public async Task<AdvisorEndpointStatus> CheckEndpointAsync(string endpoint, CancellationToken cancellationToken = default)
    {
        var check = await InvokeSingleAsync(new PSCommand().AddCommand("Get-AdvisorEndpointCheck").AddParameter("Endpoint", endpoint), cancellationToken).ConfigureAwait(false);
        var message = check.Properties["Message"]?.Value as PSObject;
        return new AdvisorEndpointStatus(
            check.Properties["Ok"]?.Value is true,
            ActionOutcome.Text(check, "Network") ?? "Invalid",
            check.Properties["Unencrypted"]?.Value is true,
            message is null ? null : ActionOutcome.Text(message, "Code"),
            SoftwareItem.MessageText(message));
    }

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
