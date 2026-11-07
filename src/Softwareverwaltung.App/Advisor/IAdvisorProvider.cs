namespace Softwareverwaltung.App.Advisor;

/// <summary>
/// Anbieter-Schnittstelle des KI-Beraters. Heute gibt es nur <see cref="OpenAiCompatibleProvider"/> für lokale
/// Server; externe Anbieter (z. B. Claude API) kommen später als Plugin mit dieser Schnittstelle, ohne Umbau.
/// Ein Anbieter überträgt nur Nachrichten und Tool-Beschreibungen. Was das Modell an Daten sieht, bestimmt
/// das Modul über die Freigabestufe der <see cref="Kind"/>; Tool-Aufrufe führt <see cref="AdvisorConversation"/> aus.
/// </summary>
public interface IAdvisorProvider : IDisposable
{
    /// <summary>Fester Name, z. B. „OpenAiCompatible“.</summary>
    string Id { get; }

    AdvisorProviderKind Kind { get; }

    /// <summary>Gewähltes Modell oder null.</summary>
    string? Model { get; }

    /// <summary>Modelle, die der Server meldet.</summary>
    Task<IReadOnlyList<string>> ListModelsAsync(CancellationToken cancellationToken = default);

    /// <summary>Eine Antwort des Modells auf das bisherige Gespräch, mit den angebotenen Tools.</summary>
    Task<AdvisorCompletion> CompleteAsync(IReadOnlyList<AdvisorMessage> messages, IReadOnlyList<AdvisorToolDefinition> tools, CancellationToken cancellationToken = default);
}
