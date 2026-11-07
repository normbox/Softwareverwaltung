using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Security;
using System.Text;
using System.Text.Json;

namespace Softwareverwaltung.App.Advisor;

/// <summary>
/// Lokale Server mit OpenAI-kompatibler Schnittstelle (Ollama, LM Studio, Unsloth Studio, eigene Adresse):
/// /models und /chat/completions mit tools, ohne Streaming. Verbindungen nur zu lokalen Adressen
/// (<see cref="LocalOnlyHttp"/>). Der Schlüssel wird erst für den Header zu Klartext und erscheint nie in Meldungen;
/// Fehler nennen nur Code und Statuscode, nie den Antworttext des Servers.
/// </summary>
public sealed class OpenAiCompatibleProvider : IAdvisorProvider
{
    public const int MaxResponseBytes = 8 * 1024 * 1024;

    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromMinutes(5);
    private readonly HttpClient _client;
    private readonly Uri _base;
    private readonly SecureString? _apiKey;

    /// <param name="handler">Nur für Tests; sonst <see cref="LocalOnlyHttp.CreateHandler"/>.</param>
    public OpenAiCompatibleProvider(AdvisorConnection connection, HttpMessageHandler? handler = null, TimeSpan? timeout = null)
    {
        if (!Uri.TryCreate(connection.Endpoint, UriKind.Absolute, out var uri)
            || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps)
            || uri.UserInfo.Length > 0)
        {
            throw new AdvisorException("AdvisorEndpointInvalid", connection.Endpoint ?? "");
        }
        _base = new Uri(uri.GetLeftPart(UriPartial.Path).TrimEnd('/') + "/");
        _client = new HttpClient(handler ?? LocalOnlyHttp.CreateHandler(), disposeHandler: true) { Timeout = timeout ?? DefaultTimeout };
        _client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("SoftwareInventory", typeof(OpenAiCompatibleProvider).Assembly.GetName().Version?.ToString(3) ?? "0"));
        Model = string.IsNullOrWhiteSpace(connection.Model) ? null : connection.Model.Trim();
        _apiKey = connection.ApiKey;
    }

    public string Id => "OpenAiCompatible";

    /// <summary>Immer lokal: Die Adresse muss Loopback oder privat sein.</summary>
    public AdvisorProviderKind Kind => AdvisorProviderKind.Local;

    public string? Model { get; }

    public async Task<IReadOnlyList<string>> ListModelsAsync(CancellationToken cancellationToken = default)
    {
        using var doc = await SendAsync(HttpMethod.Get, "models", null, cancellationToken).ConfigureAwait(false);
        if (doc.RootElement.ValueKind != JsonValueKind.Object
            || !doc.RootElement.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Array)
        {
            throw new AdvisorException("AdvisorInvalidResponse");
        }
        return data.EnumerateArray()
            .Select(m => m.ValueKind == JsonValueKind.Object && m.TryGetProperty("id", out var id) && id.ValueKind == JsonValueKind.String ? id.GetString() : null)
            .OfType<string>()
            .Where(id => id.Length > 0)
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    public async Task<AdvisorCompletion> CompleteAsync(IReadOnlyList<AdvisorMessage> messages, IReadOnlyList<AdvisorToolDefinition> tools, CancellationToken cancellationToken = default)
    {
        if (Model is null)
        {
            throw new AdvisorException("AdvisorNoModel");
        }
        using var doc = await SendAsync(HttpMethod.Post, "chat/completions", BuildRequest(Model, messages, tools), cancellationToken).ConfigureAwait(false);
        return ParseCompletion(doc.RootElement);
    }

    public void Dispose() => _client.Dispose();

    /// <summary>Anfrage im OpenAI-Format; öffentlich für Tests.</summary>
    public static string BuildRequest(string model, IReadOnlyList<AdvisorMessage> messages, IReadOnlyList<AdvisorToolDefinition> tools)
    {
        using var buffer = new MemoryStream();
        using (var w = new Utf8JsonWriter(buffer))
        {
            w.WriteStartObject();
            w.WriteString("model", model);
            w.WriteBoolean("stream", false);
            w.WriteStartArray("messages");
            foreach (var m in messages)
            {
                WriteMessage(w, m);
            }
            w.WriteEndArray();
            if (tools.Count > 0)
            {
                w.WriteStartArray("tools");
                foreach (var tool in tools)
                {
                    w.WriteStartObject();
                    w.WriteString("type", "function");
                    w.WriteStartObject("function");
                    w.WriteString("name", tool.Name);
                    w.WriteString("description", tool.Description);
                    w.WritePropertyName("parameters");
                    using (var schema = JsonDocument.Parse(tool.ParametersJson))
                    {
                        schema.WriteTo(w);
                    }
                    w.WriteEndObject();
                    w.WriteEndObject();
                }
                w.WriteEndArray();
                w.WriteString("tool_choice", "auto");
            }
            w.WriteEndObject();
        }
        return Encoding.UTF8.GetString(buffer.ToArray());
    }

    /// <summary>Antwort im OpenAI-Format; Argumente als Text oder (manche Server) als Objekt.</summary>
    public static AdvisorCompletion ParseCompletion(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object
            || !root.TryGetProperty("choices", out var choices) || choices.ValueKind != JsonValueKind.Array || choices.GetArrayLength() == 0
            || choices[0].ValueKind != JsonValueKind.Object
            || !choices[0].TryGetProperty("message", out var message) || message.ValueKind != JsonValueKind.Object)
        {
            throw new AdvisorException("AdvisorInvalidResponse");
        }
        var content = message.TryGetProperty("content", out var c) && c.ValueKind == JsonValueKind.String ? c.GetString() : null;
        var calls = new List<AdvisorToolCall>();
        if (message.TryGetProperty("tool_calls", out var toolCalls) && toolCalls.ValueKind == JsonValueKind.Array)
        {
            var index = 0;
            foreach (var call in toolCalls.EnumerateArray())
            {
                index++;
                if (call.ValueKind != JsonValueKind.Object
                    || !call.TryGetProperty("function", out var function) || function.ValueKind != JsonValueKind.Object
                    || !function.TryGetProperty("name", out var name) || name.ValueKind != JsonValueKind.String)
                {
                    throw new AdvisorException("AdvisorInvalidResponse");
                }
                var id = call.TryGetProperty("id", out var i) && i.ValueKind == JsonValueKind.String && i.GetString() is { Length: > 0 } s ? s : $"call_{index}";
                var arguments = !function.TryGetProperty("arguments", out var a) ? "{}" : a.ValueKind switch
                {
                    JsonValueKind.String => a.GetString() is { Length: > 0 } text ? text : "{}",
                    JsonValueKind.Object => a.GetRawText(),
                    _ => "{}",
                };
                calls.Add(new AdvisorToolCall(id, name.GetString()!, arguments));
            }
        }
        return new AdvisorCompletion(content, calls);
    }

    private static void WriteMessage(Utf8JsonWriter w, AdvisorMessage m)
    {
        w.WriteStartObject();
        w.WriteString("role", m.Role switch
        {
            AdvisorRole.System => "system",
            AdvisorRole.User => "user",
            AdvisorRole.Assistant => "assistant",
            _ => "tool",
        });
        if (m.Content is null)
        {
            w.WriteNull("content");
        }
        else
        {
            w.WriteString("content", m.Content);
        }
        if (m.Role == AdvisorRole.Assistant && m.ToolCalls is { Count: > 0 })
        {
            w.WriteStartArray("tool_calls");
            foreach (var call in m.ToolCalls)
            {
                w.WriteStartObject();
                w.WriteString("id", call.Id);
                w.WriteString("type", "function");
                w.WriteStartObject("function");
                w.WriteString("name", call.Name);
                w.WriteString("arguments", call.ArgumentsJson);
                w.WriteEndObject();
                w.WriteEndObject();
            }
            w.WriteEndArray();
        }
        if (m.Role == AdvisorRole.Tool)
        {
            w.WriteString("tool_call_id", m.ToolCallId);
        }
        w.WriteEndObject();
    }

    private async Task<JsonDocument> SendAsync(HttpMethod method, string path, string? body, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(method, new Uri(_base, path));
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        if (body is not null)
        {
            request.Content = new StringContent(body, Encoding.UTF8, "application/json");
        }
        if (_apiKey is { Length: > 0 })
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", Reveal(_apiKey));
        }

        try
        {
            using var response = await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
            var status = (int)response.StatusCode;
            if (status is >= 300 and < 400)
            {
                throw new AdvisorException("AdvisorRedirectRefused", status);
            }
            if (status is 401 or 403)
            {
                throw new AdvisorException("AdvisorUnauthorized", status);
            }
            if (!response.IsSuccessStatusCode)
            {
                throw new AdvisorException("AdvisorHttpError", status);
            }
            var bytes = await ReadLimitedAsync(response.Content, cancellationToken).ConfigureAwait(false);
            try
            {
                return JsonDocument.Parse(bytes);
            }
            catch (JsonException)
            {
                throw new AdvisorException("AdvisorInvalidResponse");
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new AdvisorException("AdvisorTimeout", (int)_client.Timeout.TotalSeconds);
        }
        catch (HttpRequestException ex)
        {
            throw FindAdvisorException(ex) ?? new AdvisorException("AdvisorServerUnreachable", ex, _base.Authority);
        }
    }

    private static async Task<byte[]> ReadLimitedAsync(HttpContent content, CancellationToken cancellationToken)
    {
        if (content.Headers.ContentLength > MaxResponseBytes)
        {
            throw new AdvisorException("AdvisorResponseTooLarge", MaxResponseBytes / (1024 * 1024));
        }
        await using var stream = await content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        using var result = new MemoryStream();
        var buffer = new byte[81920];
        int read;
        while ((read = await stream.ReadAsync(buffer, cancellationToken).ConfigureAwait(false)) > 0)
        {
            if (result.Length + read > MaxResponseBytes)
            {
                throw new AdvisorException("AdvisorResponseTooLarge", MaxResponseBytes / (1024 * 1024));
            }
            result.Write(buffer, 0, read);
        }
        return result.ToArray();
    }

    private static AdvisorException? FindAdvisorException(Exception? ex)
    {
        for (; ex is not null; ex = ex.InnerException)
        {
            if (ex is AdvisorException advisor)
            {
                return advisor;
            }
        }
        return null;
    }

    private static string Reveal(SecureString secret)
    {
        var pointer = Marshal.SecureStringToGlobalAllocUnicode(secret);
        try
        {
            return Marshal.PtrToStringUni(pointer) ?? "";
        }
        finally
        {
            Marshal.ZeroFreeGlobalAllocUnicode(pointer);
        }
    }
}
