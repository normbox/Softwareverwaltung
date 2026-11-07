using Softwareverwaltung.App.Localization;

namespace Softwareverwaltung.App.Advisor;

/// <summary>
/// Ergebnis von „Verbindung testen“. Code ist AdvisorTestOk, AdvisorTestChooseModel, AdvisorTestModelMissing,
/// AdvisorTestNoToolCall oder ein Fehlercode. Klappt nur der Tool-Aufruf nicht, ist das eine Warnung (Warning),
/// gespeichert werden darf trotzdem (CanSave). EndpointNote nennt z. B. „unverschlüsselt“.
/// </summary>
public sealed record AdvisorConnectionTestResult(string Code, bool Ok, bool Warning, bool CanSave, IReadOnlyList<string> Models, string Message, string? EndpointNote);

/// <summary>Einstieg für die Oberfläche: Anbieter aus den Einstellungen, Gespräch, Verbindungstest.</summary>
public sealed class AdvisorService(IAdvisorModule module, Func<AdvisorConnection, IAdvisorProvider>? createProvider = null)
{
    private readonly Func<AdvisorConnection, IAdvisorProvider> _createProvider = createProvider ?? CreateProvider;

    /// <summary>
    /// Anbieter zu den Verbindungsdaten. Heute nur der OpenAI-kompatible für lokale Server; Plugins für externe
    /// Anbieter hängen sich später hier ein.
    /// </summary>
    public static IAdvisorProvider CreateProvider(AdvisorConnection connection) => new OpenAiCompatibleProvider(connection);

    /// <summary>Neues Gespräch mit den gespeicherten Einstellungen; der Berater muss eingeschaltet sein.</summary>
    public async Task<AdvisorConversation> StartConversationAsync(CancellationToken cancellationToken = default)
    {
        var connection = await module.GetConnectionAsync(cancellationToken).ConfigureAwait(false);
        if (!connection.Enabled)
        {
            throw new AdvisorException("AdvisorDisabled");
        }
        return new AdvisorConversation(_createProvider(connection), module);
    }

    /// <summary>
    /// Prüft Adresse, Erreichbarkeit, Modelle und einen echten Tool-Aufruf. Der Tool-Aufruf wird nicht ausgeführt,
    /// es gehen also keine Inventardaten an das Modell, nur die festen Testtexte und die Tool-Beschreibung.
    /// </summary>
    /// <param name="connection">Ungespeicherte Werte aus der Einstellungsseite; ohne Angabe die gespeicherten.</param>
    public async Task<AdvisorConnectionTestResult> TestConnectionAsync(AdvisorConnection? connection = null, CancellationToken cancellationToken = default)
    {
        connection ??= await module.GetConnectionAsync(cancellationToken).ConfigureAwait(false);
        var check = await module.CheckEndpointAsync(connection.Endpoint ?? "", cancellationToken).ConfigureAwait(false);
        if (!check.Ok)
        {
            return Fail(check.Code ?? "AdvisorEndpointInvalid", check.Message ?? AppText.Format("AdvisorEndpointInvalid", connection.Endpoint ?? ""), [], null);
        }
        var note = check.Unencrypted ? check.Message : null;

        IAdvisorProvider provider;
        try
        {
            provider = _createProvider(connection);
        }
        catch (AdvisorException ex)
        {
            return Fail(ex.Code, ex.Message, [], note);
        }
        using (provider)
        {
            IReadOnlyList<string> models;
            try
            {
                models = await provider.ListModelsAsync(cancellationToken).ConfigureAwait(false);
            }
            catch (AdvisorException ex)
            {
                return Fail(ex.Code, ex.Message, [], note);
            }
            if (provider.Model is null)
            {
                return new AdvisorConnectionTestResult("AdvisorTestChooseModel", true, false, true, models, AppText.Format("AdvisorTestChooseModel", models.Count), note);
            }
            if (!models.Contains(provider.Model, StringComparer.Ordinal))
            {
                return new AdvisorConnectionTestResult("AdvisorTestModelMissing", false, false, false, models, AppText.Format("AdvisorTestModelMissing", provider.Model), note);
            }

            var tool = (await module.GetToolsAsync(provider.Kind, cancellationToken).ConfigureAwait(false)).Where(t => t.Name == "get_inventory").ToList();
            AdvisorCompletion completion;
            try
            {
                completion = await provider.CompleteAsync(
                    [AdvisorMessage.System(AppText.Get("AdvisorTestSystemPrompt")), AdvisorMessage.User(AppText.Get("AdvisorTestUserPrompt"))],
                    tool, cancellationToken).ConfigureAwait(false);
            }
            catch (AdvisorException ex)
            {
                // Server und Modell sind da, nur die Antwort klappt nicht: Warnung, Speichern bleibt möglich.
                return new AdvisorConnectionTestResult(ex.Code, false, true, true, models, AppText.Format("AdvisorTestToolCallFailed", ex.Message), note);
            }
            return completion.ToolCalls.Any(c => c.Name == "get_inventory")
                ? new AdvisorConnectionTestResult("AdvisorTestOk", true, false, true, models, AppText.Format("AdvisorTestOk", provider.Model), note)
                : new AdvisorConnectionTestResult("AdvisorTestNoToolCall", false, true, true, models, AppText.Format("AdvisorTestNoToolCall", provider.Model), note);
        }

        static AdvisorConnectionTestResult Fail(string code, string message, IReadOnlyList<string> models, string? note) =>
            new(code, false, false, false, models, message, note);
    }
}
