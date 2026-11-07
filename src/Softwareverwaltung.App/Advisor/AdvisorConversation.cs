using System.Management.Automation;

namespace Softwareverwaltung.App.Advisor;

/// <summary>
/// Gesprächsschleife des Beraters: Frage bereinigen, Modell fragen, Tool-Aufrufe über das Modul ausführen und
/// die Ergebnisse zurückgeben, bis das Modell antwortet. Systemanweisung und Tools kommen aus dem Modul, passend
/// zur Freigabestufe der Anbieterart. Vorschläge werden nur gesammelt (Karten in Etappe 4c); ausgeführt wird nichts.
/// Läuft gerade ein Scan, warten die Tool-Aufrufe an der Sperre des PowerShell-Hosts; Dienste werden also nie
/// parallel zu einem Scan abgefragt. Das Gespräch liegt nur im Speicher; ab <see cref="MaxQuestions"/> Fragen
/// fallen die ältesten Runden weg.
/// </summary>
public sealed class AdvisorConversation(IAdvisorProvider provider, IAdvisorModule module, int maxToolRounds = AdvisorConversation.DefaultMaxToolRounds)
    : IAdvisorChatSession
{
    public const int DefaultMaxToolRounds = 8;

    /// <summary>Höchstens so viele Fragen samt Antworten und Tool-Runden bleiben im Gespräch.</summary>
    public const int MaxQuestions = 20;

    private readonly List<AdvisorMessage> _messages = [];
    private IReadOnlyList<AdvisorToolDefinition>? _tools;

    public IAdvisorProvider Provider => provider;

    /// <summary>Bisheriges Gespräch, wie es an das Modell geht.</summary>
    public IReadOnlyList<AdvisorMessage> Messages => _messages;

    /// <summary>
    /// Stellt eine Frage. Bei einem Fehler bleibt das Gespräch wie vorher (keine halben Tool-Runden).
    /// Nach <see cref="DefaultMaxToolRounds"/> Runden mit Tool-Aufrufen bricht die Schleife mit AdvisorToolRoundLimit ab.
    /// </summary>
    public async Task<AdvisorReply> AskAsync(string question, CancellationToken cancellationToken = default)
    {
        var start = _messages.Count;
        List<AdvisorMessage>? removed = null;
        try
        {
            if (_tools is null)
            {
                var prompt = await module.GetSystemPromptAsync(cancellationToken).ConfigureAwait(false);
                var tools = await module.GetToolsAsync(provider.Kind, cancellationToken).ConfigureAwait(false);
                _messages.Add(AdvisorMessage.System(prompt));
                _tools = tools;
            }
            var protectedQuestion = await module.ProtectTextAsync(question, cancellationToken).ConfigureAwait(false);
            removed = TrimOldestQuestions();
            start -= removed?.Count ?? 0;
            _messages.Add(AdvisorMessage.User(protectedQuestion));

            var proposals = new List<PSObject>();
            var toolNames = new List<string>();
            for (var round = 0; ; round++)
            {
                var completion = await provider.CompleteAsync(_messages, _tools, cancellationToken).ConfigureAwait(false);
                if (completion.ToolCalls.Count == 0)
                {
                    var text = completion.Content ?? "";
                    _messages.Add(AdvisorMessage.Assistant(text));
                    return new AdvisorReply(text, proposals, round, toolNames);
                }
                if (round >= maxToolRounds)
                {
                    throw new AdvisorException("AdvisorToolRoundLimit", maxToolRounds);
                }
                _messages.Add(AdvisorMessage.Assistant(completion.Content, completion.ToolCalls));
                foreach (var call in completion.ToolCalls)
                {
                    toolNames.Add(call.Name);
                    var result = await module.InvokeToolAsync(call.Name, call.ArgumentsJson, provider.Kind, cancellationToken).ConfigureAwait(false);
                    if (result.Proposal is not null)
                    {
                        proposals.Add(result.Proposal);
                    }
                    _messages.Add(AdvisorMessage.ToolResult(call.Id, result.Content));
                }
            }
        }
        catch
        {
            _messages.RemoveRange(start, _messages.Count - start);
            if (removed is not null)
            {
                // Weggefallene alte Runden zurückholen, damit das Gespräch genau wie vor der Frage ist.
                _messages.InsertRange(1, removed);
            }
            if (start == 0)
            {
                _tools = null;
            }
            throw;
        }
    }

    /// <summary>
    /// Entfernt die ältesten Runden (Frage bis vor die nächste Frage), bis Platz für eine neue Frage ist.
    /// Liefert die entfernten Nachrichten oder null.
    /// </summary>
    private List<AdvisorMessage>? TrimOldestQuestions()
    {
        List<AdvisorMessage>? trimmed = null;
        while (_messages.Count(m => m.Role == AdvisorRole.User) >= MaxQuestions)
        {
            var first = _messages.FindIndex(1, m => m.Role == AdvisorRole.User);
            var next = _messages.FindIndex(first + 1, m => m.Role == AdvisorRole.User);
            var count = next - first;
            (trimmed ??= []).AddRange(_messages.GetRange(first, count));
            _messages.RemoveRange(first, count);
        }
        return trimmed;
    }

    public void Dispose() => provider.Dispose();
}

/// <summary>Ein laufendes Gespräch für die Seitenleiste; eigene Schnittstelle für Tests des ViewModels.</summary>
public interface IAdvisorChatSession : IDisposable
{
    Task<AdvisorReply> AskAsync(string question, CancellationToken cancellationToken = default);
}
