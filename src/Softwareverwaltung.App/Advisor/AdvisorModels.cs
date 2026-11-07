using System.Management.Automation;
using System.Security;
using Softwareverwaltung.App.Localization;

namespace Softwareverwaltung.App.Advisor;

/// <summary>Art des Anbieters; das Modul bestimmt daraus die Freigabestufe (Local höchstens 4, External höchstens 3).</summary>
public enum AdvisorProviderKind
{
    Local,
    External,
}

public enum AdvisorRole
{
    System,
    User,
    Assistant,
    Tool,
}

/// <summary>Tool-Aufruf des Modells. ArgumentsJson ist das JSON-Objekt, wie es das Modell geliefert hat.</summary>
public sealed record AdvisorToolCall(string Id, string Name, string ArgumentsJson);

/// <summary>
/// Nachricht im Gespräch, unabhängig vom Format eines Servers. Ein Anbieter wandelt sie selbst um
/// (OpenAI-kompatibel heute, später z. B. Claude als Plugin).
/// </summary>
public sealed record AdvisorMessage(AdvisorRole Role, string? Content, IReadOnlyList<AdvisorToolCall>? ToolCalls = null, string? ToolCallId = null)
{
    public static AdvisorMessage System(string content) => new(AdvisorRole.System, content);

    public static AdvisorMessage User(string content) => new(AdvisorRole.User, content);

    public static AdvisorMessage Assistant(string? content, IReadOnlyList<AdvisorToolCall>? toolCalls = null) => new(AdvisorRole.Assistant, content, toolCalls);

    public static AdvisorMessage ToolResult(string toolCallId, string content) => new(AdvisorRole.Tool, content, ToolCallId: toolCallId);
}

/// <summary>Tool aus Get-AdvisorTool: Kind ist Read oder Proposal, ParametersJson ein JSON-Schema.</summary>
public sealed record AdvisorToolDefinition(string Name, string Kind, string Description, string ParametersJson)
{
    public static AdvisorToolDefinition FromPs(PSObject tool) => new(
        tool.Properties["Name"]?.Value?.ToString() ?? "",
        tool.Properties["Kind"]?.Value?.ToString() ?? "",
        tool.Properties["Description"]?.Value?.ToString() ?? "",
        tool.Properties["ParametersJson"]?.Value?.ToString() ?? "{}");
}

/// <summary>Antwort des Modells: Text, Tool-Aufrufe oder beides.</summary>
public sealed record AdvisorCompletion(string? Content, IReadOnlyList<AdvisorToolCall> ToolCalls);

/// <summary>Verbindungsdaten aus Get-AdvisorConnection. Der Schlüssel bleibt ein SecureString bis zum Header.</summary>
public sealed record AdvisorConnection(bool Enabled, string? Preset, string? Endpoint, string? Model, AdvisorProviderKind Kind, SecureString? ApiKey)
{
    public static AdvisorConnection FromPs(PSObject connection) => new(
        connection.Properties["Enabled"]?.Value is true,
        connection.Properties["Preset"]?.Value?.ToString(),
        connection.Properties["Endpoint"]?.Value?.ToString(),
        connection.Properties["Model"]?.Value?.ToString(),
        Enum.TryParse<AdvisorProviderKind>(connection.Properties["ProviderKind"]?.Value?.ToString(), out var kind) ? kind : AdvisorProviderKind.Local,
        (connection.Properties["ApiKey"]?.Value as PSObject)?.BaseObject as SecureString ?? connection.Properties["ApiKey"]?.Value as SecureString);
}

/// <summary>Ergebnis von Invoke-AdvisorTool: Content geht an das Modell, Proposal nur an die Oberfläche.</summary>
public sealed record AdvisorToolResult(string Name, bool Ok, string? Code, string Content, PSObject? Proposal);

/// <summary>Antwort auf eine Frage: Text des Modells und die Vorschläge für die Karten (Etappe 4c).</summary>
public sealed record AdvisorReply(string Text, IReadOnlyList<PSObject> Proposals, int ToolRounds);

/// <summary>
/// Fehler des Beraters mit festem Code (z. B. AdvisorEndpointNotLocal, gleichnamiger Text in Strings.resx). Der Text enthält
/// nie den API-Schlüssel, keine Header und keinen Antworttext des Servers.
/// </summary>
public sealed class AdvisorException : Exception
{
    public AdvisorException(string code, params object?[] args) : base(AppText.Format(code, args))
    {
        Code = code;
        Args = args;
    }

    public AdvisorException(string code, Exception inner, params object?[] args) : base(AppText.Format(code, args), inner)
    {
        Code = code;
        Args = args;
    }

    public string Code { get; }

    public IReadOnlyList<object?> Args { get; }
}
