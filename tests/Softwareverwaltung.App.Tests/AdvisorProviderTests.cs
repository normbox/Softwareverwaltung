using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Runtime.CompilerServices;
using System.Security;
using System.Text;
using System.Text.Json;
using Softwareverwaltung.App.Advisor;

namespace Softwareverwaltung.App.Tests;

/// <summary>Adressprüfung beim Verbinden und das OpenAI-kompatible Format, ohne echten KI-Server.</summary>
public sealed class AdvisorProviderTests
{
    private const string Key = "sk-test-SECRET-1234567890";

    [Fact]
    public void AddressRuleMatchesTheSharedTableWithTheModule()
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(TestFolder(), "Data", "advisor-address-cases.json")));
        var cases = doc.RootElement.GetProperty("cases").EnumerateArray().ToList();
        Assert.True(cases.Count >= 20);
        var wrong = cases
            .Select(c => (Address: c.GetProperty("address").GetString()!, Expected: c.GetProperty("network").GetString()!))
            .Select(c => (c.Address, c.Expected, Actual: LocalAddressPolicy.Classify(IPAddress.Parse(c.Address)).ToString()))
            .Where(c => c.Expected != c.Actual)
            .ToList();
        Assert.Empty(wrong);
    }

    [Fact]
    public void HandlerFollowsNoRedirectsUsesNoProxyAndKeepsTlsDefaults()
    {
        using var handler = LocalOnlyHttp.CreateHandler();
        Assert.False(handler.AllowAutoRedirect);
        Assert.False(handler.UseProxy);
        Assert.False(handler.UseCookies);
        Assert.NotNull(handler.ConnectCallback);
        // TLS prüft weiter gegen den Hostnamen der Anfrage: kein eigener Zielname, keine eigene Zertifikatsprüfung
        Assert.Null(handler.SslOptions.TargetHost);
        Assert.Null(handler.SslOptions.RemoteCertificateValidationCallback);
    }

    [Theory]
    [InlineData("cloud.example", "203.0.113.10")]
    [InlineData("localhost.evil.example", "203.0.113.99")]
    [InlineData("mixed.lan", "192.168.1.21,8.8.8.8")]
    [InlineData("tailnet.example", "100.64.1.1")]
    public async Task ConnectRefusesPublicAddressesBeforeConnecting(string host, string addresses)
    {
        var resolved = addresses.Split(',').Select(IPAddress.Parse).ToArray();
        var ex = await Assert.ThrowsAsync<AdvisorException>(async () =>
            await LocalOnlyHttp.ConnectAsync(new DnsEndPoint(host, 11434), (_, _) => Task.FromResult(resolved), CancellationToken.None));
        Assert.Equal("AdvisorEndpointNotLocal", ex.Code);
    }

    [Fact]
    public async Task ConnectRefusesUnresolvableNames()
    {
        var ex = await Assert.ThrowsAsync<AdvisorException>(async () =>
            await LocalOnlyHttp.ConnectAsync(new DnsEndPoint("nowhere.invalid", 80), (_, _) => Task.FromResult(Array.Empty<IPAddress>()), CancellationToken.None));
        Assert.Equal("AdvisorEndpointUnresolvable", ex.Code);
    }

    [Fact]
    public async Task RealResolverTreatsIpLiteralsAndUnknownNamesCorrectly()
    {
        Assert.Equal([IPAddress.IPv6Loopback], await LocalOnlyHttp.ResolveAsync("::1", CancellationToken.None));
        Assert.Empty(await LocalOnlyHttp.ResolveAsync("nowhere.invalid", CancellationToken.None));
    }

    [Fact]
    public async Task ProviderTalksToALocalServerThroughTheCheckedConnection()
    {
        await using var server = new TinyHttpServer(_ => (200, """{"object":"list","data":[{"id":"qwen3:8b"},{"id":"llama3.2"}]}""", null));
        // Der Name wird über die Prüfung auf Loopback aufgelöst; verbunden wird nur zur geprüften Adresse.
        using var provider = new OpenAiCompatibleProvider(
            Connection($"http://my-ai-box:{server.Port}/v1"),
            LocalOnlyHttp.CreateHandler((_, _) => Task.FromResult(new[] { IPAddress.Loopback })));

        var models = await provider.ListModelsAsync();

        Assert.Equal(["llama3.2", "qwen3:8b"], models);
        Assert.StartsWith("GET /v1/models ", server.Requests.Single());
        Assert.Contains($"Authorization: Bearer {Key}", server.Requests.Single());
        Assert.Contains("User-Agent: SoftwareInventory/", server.Requests.Single());
    }

    [Fact]
    public async Task ProviderSurfacesTheAddressCodeWhenTheNameIsPublic()
    {
        using var provider = new OpenAiCompatibleProvider(
            Connection("http://cloud.example:11434/v1"),
            LocalOnlyHttp.CreateHandler((_, _) => Task.FromResult(new[] { IPAddress.Parse("203.0.113.10") })));

        var ex = await Assert.ThrowsAsync<AdvisorException>(() => provider.ListModelsAsync());

        Assert.Equal("AdvisorEndpointNotLocal", ex.Code);
    }

    [Fact]
    public async Task RedirectsAreNotFollowed()
    {
        await using var server = new TinyHttpServer(_ => (302, "", "Location: https://example.com/v1/models"));
        using var provider = new OpenAiCompatibleProvider(Connection($"http://127.0.0.1:{server.Port}/v1"));

        var ex = await Assert.ThrowsAsync<AdvisorException>(() => provider.ListModelsAsync());

        Assert.Equal("AdvisorRedirectRefused", ex.Code);
        Assert.Single(server.Requests);
    }

    [Fact]
    public async Task ClosedPortIsUnreachable()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        using var provider = new OpenAiCompatibleProvider(Connection($"http://127.0.0.1:{port}/v1"));

        var ex = await Assert.ThrowsAsync<AdvisorException>(() => provider.ListModelsAsync());

        Assert.Equal("AdvisorServerUnreachable", ex.Code);
        Assert.DoesNotContain(Key, ex.ToString());
    }

    [Theory]
    [InlineData("ftp://localhost/v1")]
    [InlineData("http://user:pw@localhost/v1")]
    [InlineData("localhost:11434")]
    [InlineData("")]
    public void InvalidEndpointsAreRefused(string endpoint)
    {
        var ex = Assert.Throws<AdvisorException>(() => new OpenAiCompatibleProvider(Connection(endpoint)));
        Assert.Equal("AdvisorEndpointInvalid", ex.Code);
    }

    [Fact]
    public void RequestUsesOpenAiToolFormat()
    {
        var call = new AdvisorToolCall("call_1", "get_program_details", """{"id":"p-0123456789ab"}""");
        var json = OpenAiCompatibleProvider.BuildRequest("qwen3:8b",
            [
                AdvisorMessage.System("sys"),
                AdvisorMessage.User("frage"),
                AdvisorMessage.Assistant(null, [call]),
                AdvisorMessage.ToolResult("call_1", """{"ok":true}"""),
            ],
            [new AdvisorToolDefinition("get_program_details", "Read", "Details", """{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}""")]);

        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        Assert.Equal("qwen3:8b", root.GetProperty("model").GetString());
        Assert.False(root.GetProperty("stream").GetBoolean());
        Assert.Equal("auto", root.GetProperty("tool_choice").GetString());
        var tool = root.GetProperty("tools")[0];
        Assert.Equal("function", tool.GetProperty("type").GetString());
        Assert.Equal("get_program_details", tool.GetProperty("function").GetProperty("name").GetString());
        Assert.Equal("id", tool.GetProperty("function").GetProperty("parameters").GetProperty("required")[0].GetString());
        var messages = root.GetProperty("messages");
        Assert.Equal(["system", "user", "assistant", "tool"], messages.EnumerateArray().Select(m => m.GetProperty("role").GetString()));
        Assert.Equal(JsonValueKind.Null, messages[2].GetProperty("content").ValueKind);
        var sent = messages[2].GetProperty("tool_calls")[0];
        Assert.Equal("call_1", sent.GetProperty("id").GetString());
        Assert.Equal("""{"id":"p-0123456789ab"}""", sent.GetProperty("function").GetProperty("arguments").GetString());
        Assert.Equal("call_1", messages[3].GetProperty("tool_call_id").GetString());
    }

    [Fact]
    public void RequestWithoutToolsHasNoToolFields()
    {
        using var doc = JsonDocument.Parse(OpenAiCompatibleProvider.BuildRequest("m", [AdvisorMessage.User("hi")], []));
        Assert.False(doc.RootElement.TryGetProperty("tools", out _));
        Assert.False(doc.RootElement.TryGetProperty("tool_choice", out _));
    }

    [Fact]
    public void ParsesToolCallsWithTextObjectOrMissingArguments()
    {
        using var doc = JsonDocument.Parse("""
            {"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[
              {"id":"a","type":"function","function":{"name":"get_inventory","arguments":"{\"limit\":5}"}},
              {"type":"function","function":{"name":"get_program_details","arguments":{"id":"p-0123456789ab"}}},
              {"id":"","function":{"name":"get_inventory"}}
            ]}}]}
            """);

        var completion = OpenAiCompatibleProvider.ParseCompletion(doc.RootElement);

        Assert.Null(completion.Content);
        Assert.Equal(3, completion.ToolCalls.Count);
        Assert.Equal(new AdvisorToolCall("a", "get_inventory", """{"limit":5}"""), completion.ToolCalls[0]);
        Assert.Equal("call_2", completion.ToolCalls[1].Id);
        Assert.Equal("p-0123456789ab", JsonDocument.Parse(completion.ToolCalls[1].ArgumentsJson).RootElement.GetProperty("id").GetString());
        Assert.Equal("{}", completion.ToolCalls[2].ArgumentsJson);
        Assert.Equal("call_3", completion.ToolCalls[2].Id);
    }

    [Theory]
    [InlineData("""{"choices":[]}""")]
    [InlineData("""{"choices":[{"message":"text"}]}""")]
    [InlineData("""{"choices":[{"message":{"tool_calls":[{"function":{}}]}}]}""")]
    [InlineData("""[1,2]""")]
    public void BrokenCompletionsAreInvalidResponses(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var ex = Assert.Throws<AdvisorException>(() => OpenAiCompatibleProvider.ParseCompletion(doc.RootElement));
        Assert.Equal("AdvisorInvalidResponse", ex.Code);
    }

    [Fact]
    public async Task CompletionSendsKeyOnlyInTheHeader()
    {
        var handler = new FakeHandler(_ => Json(HttpStatusCode.OK, """{"choices":[{"message":{"content":"Hallo"}}]}"""));
        using var provider = new OpenAiCompatibleProvider(Connection("http://localhost:11434/v1/", "qwen3:8b"), handler);

        var completion = await provider.CompleteAsync([AdvisorMessage.User("hi")], []);

        Assert.Equal("Hallo", completion.Content);
        var request = handler.Requests.Single();
        Assert.Equal("http://localhost:11434/v1/chat/completions", request.Uri);
        Assert.Equal($"Bearer {Key}", request.Authorization);
        Assert.DoesNotContain(Key, request.Body);
    }

    [Fact]
    public async Task WithoutKeyThereIsNoAuthorizationHeader()
    {
        var handler = new FakeHandler(_ => Json(HttpStatusCode.OK, """{"data":[]}"""));
        using var provider = new OpenAiCompatibleProvider(Connection("http://localhost:11434/v1") with { ApiKey = null }, handler);

        Assert.Empty(await provider.ListModelsAsync());
        Assert.Null(handler.Requests.Single().Authorization);
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized, "AdvisorUnauthorized")]
    [InlineData(HttpStatusCode.Forbidden, "AdvisorUnauthorized")]
    [InlineData(HttpStatusCode.BadRequest, "AdvisorHttpError")]
    [InlineData(HttpStatusCode.InternalServerError, "AdvisorHttpError")]
    public async Task ErrorsNameTheStatusButNeverTheKeyOrTheServerText(HttpStatusCode status, string code)
    {
        var handler = new FakeHandler(_ => Json(status, $$"""{"error":"bad key {{Key}} at C:\\Users\\someone"}"""));
        using var provider = new OpenAiCompatibleProvider(Connection("http://localhost:11434/v1", "m"), handler);

        var ex = await Assert.ThrowsAsync<AdvisorException>(() => provider.CompleteAsync([AdvisorMessage.User("hi")], []));

        Assert.Equal(code, ex.Code);
        Assert.Contains(((int)status).ToString(), ex.Message);
        Assert.DoesNotContain(Key, ex.ToString());
        Assert.DoesNotContain("someone", ex.ToString());
    }

    [Fact]
    public async Task NonJsonAnswerIsInvalidResponse()
    {
        var handler = new FakeHandler(_ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("<html>login</html>") });
        using var provider = new OpenAiCompatibleProvider(Connection("http://localhost:11434/v1"), handler);

        Assert.Equal("AdvisorInvalidResponse", (await Assert.ThrowsAsync<AdvisorException>(() => provider.ListModelsAsync())).Code);
    }

    [Fact]
    public async Task OversizedAnswerIsDiscarded()
    {
        var big = new string('x', OpenAiCompatibleProvider.MaxResponseBytes + 10);
        var handler = new FakeHandler(_ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(new MemoryStream(Encoding.ASCII.GetBytes(big))) });
        using var provider = new OpenAiCompatibleProvider(Connection("http://localhost:11434/v1"), handler);

        Assert.Equal("AdvisorResponseTooLarge", (await Assert.ThrowsAsync<AdvisorException>(() => provider.ListModelsAsync())).Code);
    }

    [Fact]
    public async Task SlowServerTimesOutButUserCancelStaysACancel()
    {
        var handler = new FakeHandler(async (_, token) =>
        {
            await Task.Delay(TimeSpan.FromSeconds(10), token);
            return Json(HttpStatusCode.OK, "{}");
        });
        using var provider = new OpenAiCompatibleProvider(Connection("http://localhost:11434/v1"), handler, TimeSpan.FromMilliseconds(200));

        Assert.Equal("AdvisorTimeout", (await Assert.ThrowsAsync<AdvisorException>(() => provider.ListModelsAsync())).Code);

        using var cancel = new CancellationTokenSource(TimeSpan.FromMilliseconds(50));
        using var patient = new OpenAiCompatibleProvider(Connection("http://localhost:11434/v1"), new FakeHandler(async (_, token) =>
        {
            await Task.Delay(TimeSpan.FromSeconds(10), token);
            return Json(HttpStatusCode.OK, "{}");
        }));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => patient.ListModelsAsync(cancel.Token));
    }

    [Fact]
    public async Task CompletionWithoutModelIsRefusedBeforeSending()
    {
        var handler = new FakeHandler(_ => Json(HttpStatusCode.OK, "{}"));
        using var provider = new OpenAiCompatibleProvider(Connection("http://localhost:11434/v1", model: " "), handler);

        Assert.Equal("AdvisorNoModel", (await Assert.ThrowsAsync<AdvisorException>(() => provider.CompleteAsync([AdvisorMessage.User("hi")], []))).Code);
        Assert.Empty(handler.Requests);
    }

    internal static AdvisorConnection Connection(string endpoint, string? model = "qwen3:8b")
    {
        var key = new SecureString();
        foreach (var c in Key)
        {
            key.AppendChar(c);
        }
        key.MakeReadOnly();
        return new AdvisorConnection(true, "Custom", endpoint, model, AdvisorProviderKind.Local, key);
    }

    private static HttpResponseMessage Json(HttpStatusCode status, string body) =>
        new(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };

    private static string TestFolder([CallerFilePath] string sourceFile = "") => Path.GetDirectoryName(Path.GetDirectoryName(sourceFile)!)!;

    private sealed record SeenRequest(string Uri, string? Authorization, string Body);

    private sealed class FakeHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> respond) : HttpMessageHandler
    {
        public FakeHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : this((r, _) => Task.FromResult(respond(r)))
        {
        }

        public List<SeenRequest> Requests { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
            Requests.Add(new SeenRequest(request.RequestUri!.ToString(), request.Headers.Authorization?.ToString(), body));
            return await respond(request, cancellationToken);
        }
    }

    /// <summary>Kleinster HTTP-Server auf Loopback: beantwortet jede Anfrage einmal und schließt die Verbindung.</summary>
    private sealed class TinyHttpServer : IAsyncDisposable
    {
        private readonly TcpListener _listener = new(IPAddress.Loopback, 0);
        private readonly CancellationTokenSource _stop = new();
        private readonly Task _loop;

        public TinyHttpServer(Func<string, (int Status, string Body, string? Header)> respond)
        {
            _listener.Start();
            Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
            _loop = Task.Run(async () =>
            {
                while (!_stop.IsCancellationRequested)
                {
                    using var client = await _listener.AcceptTcpClientAsync(_stop.Token);
                    var stream = client.GetStream();
                    var head = await ReadHeadAsync(stream);
                    Requests.Add(head);
                    var (status, body, header) = respond(head);
                    var bytes = Encoding.UTF8.GetBytes(body);
                    var response = $"HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {bytes.Length}\r\nConnection: close\r\n{(header is null ? "" : header + "\r\n")}\r\n";
                    await stream.WriteAsync(Encoding.ASCII.GetBytes(response));
                    await stream.WriteAsync(bytes);
                }
            });
        }

        public int Port { get; }

        public List<string> Requests { get; } = [];

        public async ValueTask DisposeAsync()
        {
            _stop.Cancel();
            _listener.Stop();
            try
            {
                await _loop;
            }
            catch (Exception ex) when (ex is OperationCanceledException or SocketException or ObjectDisposedException)
            {
            }
            _stop.Dispose();
        }

        private static async Task<string> ReadHeadAsync(NetworkStream stream)
        {
            var data = new List<byte>();
            var buffer = new byte[1];
            while (await stream.ReadAsync(buffer) == 1)
            {
                data.Add(buffer[0]);
                if (data.Count >= 4 && data[^4] == '\r' && data[^3] == '\n' && data[^2] == '\r' && data[^1] == '\n')
                {
                    break;
                }
            }
            return Encoding.ASCII.GetString(data.ToArray());
        }
    }
}
