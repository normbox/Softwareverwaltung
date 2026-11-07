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

/// <summary>
/// Antwort des Modells: Text, Tool-Aufrufe oder beides. FinishReason wie vom Server gemeldet, z. B. „stop“,
/// „tool_calls“ oder „length“ (Grenze max_tokens erreicht).
/// </summary>
public sealed record AdvisorCompletion(string? Content, IReadOnlyList<AdvisorToolCall> ToolCalls, string? FinishReason = null);

/// <summary>
/// Verbindungsdaten aus Get-AdvisorConnection. Der Schlüssel bleibt ein SecureString bis zum Header.
/// MaxTokens geht als max_tokens in jede Anfrage, TimeoutSeconds ist die Zeitgrenze je Anfrage.
/// </summary>
public sealed record AdvisorConnection(bool Enabled, string? Preset, string? Endpoint, string? Model, AdvisorProviderKind Kind, SecureString? ApiKey,
    int MaxTokens = AdvisorConnection.DefaultMaxTokens, int TimeoutSeconds = AdvisorConnection.DefaultTimeoutSeconds)
{
    public const int DefaultMaxTokens = 8192;
    public const int DefaultTimeoutSeconds = 300;

    public static AdvisorConnection FromPs(PSObject connection) => new(
        connection.Properties["Enabled"]?.Value is true,
        connection.Properties["Preset"]?.Value?.ToString(),
        connection.Properties["Endpoint"]?.Value?.ToString(),
        connection.Properties["Model"]?.Value?.ToString(),
        Enum.TryParse<AdvisorProviderKind>(connection.Properties["ProviderKind"]?.Value?.ToString(), out var kind) ? kind : AdvisorProviderKind.Local,
        (connection.Properties["ApiKey"]?.Value as PSObject)?.BaseObject as SecureString ?? connection.Properties["ApiKey"]?.Value as SecureString,
        Positive(connection.Properties["MaxTokens"]?.Value, DefaultMaxTokens),
        Positive(connection.Properties["TimeoutSeconds"]?.Value, DefaultTimeoutSeconds));

    private static int Positive(object? value, int fallback) =>
        value is not null && int.TryParse(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture), out var n) && n > 0 ? n : fallback;
}

/// <summary>Ergebnis von Invoke-AdvisorTool: Content geht an das Modell, Proposal nur an die Oberfläche.</summary>
public sealed record AdvisorToolResult(string Name, bool Ok, string? Code, string Content, PSObject? Proposal);

/// <summary>Get-AdvisorDataPreview: genau das bereinigte JSON, das das Modell auf dieser Stufe bekäme.</summary>
public sealed record AdvisorDataPreview(int Level, bool HasScanData, string Inventory, string? Details);

/// <summary>Ungespeicherte Werte der Einstellungsseite für Modellliste und Verbindungstest.</summary>
public sealed record AdvisorDraft(string? Preset, string? Endpoint, string? Model);

/// <summary>
/// Antwort auf eine Frage: Text des Modells, die Vorschläge für die Karten und die Namen der aufgerufenen Tools
/// in Reihenfolge (für die Zeile „Abgefragt: …“ unter der Antwort).
/// </summary>
public sealed record AdvisorReply(string Text, IReadOnlyList<PSObject> Proposals, int ToolRounds, IReadOnlyList<string> ToolNames);

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

    /// <summary>Fehler mit fertigem Text, z. B. aus einer Meldung des Moduls (Code, Args, Text).</summary>
    public static AdvisorException WithText(string code, string text) => new(code, text, isText: true);

    private AdvisorException(string code, string text, bool isText) : base(text)
    {
        _ = isText;
        Code = code;
        Args = [];
    }

    public string Code { get; }

    public IReadOnlyList<object?> Args { get; }
}
