using System.Management.Automation;

namespace Softwareverwaltung.App.Advisor;

/// <summary>
/// Gesprächsschleife des Beraters: Frage bereinigen, Modell fragen, Tool-Aufrufe über das Modul ausführen und
/// die Ergebnisse zurückgeben, bis das Modell antwortet. Systemanweisung und Tools kommen aus dem Modul, passend
/// zur Freigabestufe der Anbieterart. Vorschläge werden nur gesammelt (Karten in Etappe 4c); ausgeführt wird nichts.
/// Läuft gerade ein Scan, warten die Tool-Aufrufe an der Sperre des PowerShell-Hosts; Dienste werden also nie
/// parallel zu einem Scan abgefragt.
/// </summary>
public sealed class AdvisorConversation(IAdvisorProvider provider, IAdvisorModule module, int maxToolRounds = AdvisorConversation.DefaultMaxToolRounds)
{
    public const int DefaultMaxToolRounds = 8;

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
        try
        {
            if (_tools is null)
            {
                var prompt = await module.GetSystemPromptAsync(cancellationToken).ConfigureAwait(false);
                var tools = await module.GetToolsAsync(provider.Kind, cancellationToken).ConfigureAwait(false);
                _messages.Add(AdvisorMessage.System(prompt));
                _tools = tools;
            }
            _messages.Add(AdvisorMessage.User(await module.ProtectTextAsync(question, cancellationToken).ConfigureAwait(false)));

            var proposals = new List<PSObject>();
            for (var round = 0; ; round++)
            {
                var completion = await provider.CompleteAsync(_messages, _tools, cancellationToken).ConfigureAwait(false);
                if (completion.ToolCalls.Count == 0)
                {
                    var text = completion.Content ?? "";
                    _messages.Add(AdvisorMessage.Assistant(text));
                    return new AdvisorReply(text, proposals, round);
                }
                if (round >= maxToolRounds)
                {
                    throw new AdvisorException("AdvisorToolRoundLimit", maxToolRounds);
                }
                _messages.Add(AdvisorMessage.Assistant(completion.Content, completion.ToolCalls));
                foreach (var call in completion.ToolCalls)
                {
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
            if (start == 0)
            {
                _tools = null;
            }
            throw;
        }
    }
}
