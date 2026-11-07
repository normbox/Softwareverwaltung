using System.Management.Automation;
using System.Net;
using System.Runtime.InteropServices;
using Softwareverwaltung.App.Advisor;
using Softwareverwaltung.App.Services;

namespace Softwareverwaltung.App.Tests;

/// <summary>Gesprächsschleife und Verbindungstest mit vorgegebenem Modell und vorgegebenem Modul.</summary>
public sealed class AdvisorConversationTests
{
    [Fact]
    public async Task ToolCallsRunThroughTheModuleUntilTheModelAnswers()
    {
        var provider = new ScriptedProvider(
            Calls(("c1", "get_inventory", """{"rating":"Red"}""")),
            Calls(("c2", "propose_update", """{"id":"p-0123456789ab","reason":"Lücke"}"""), ("c3", "get_program_details", """{"id":"p-0123456789ab"}""")),
            new AdvisorCompletion("Fertig.", []));
        var module = new FakeModule();
        var conversation = new AdvisorConversation(provider, module);

        var reply = await conversation.AskAsync("Was ist rot?");

        Assert.Equal("Fertig.", reply.Text);
        Assert.Equal(2, reply.ToolRounds);
        Assert.Single(reply.Proposals);
        Assert.Equal(["get_inventory", "propose_update", "get_program_details"], module.Invoked.Select(i => i.Name));
        Assert.All(module.Invoked, i => Assert.Equal(AdvisorProviderKind.Local, i.Kind));
        var roles = conversation.Messages.Select(m => m.Role).ToList();
        Assert.Equal([AdvisorRole.System, AdvisorRole.User, AdvisorRole.Assistant, AdvisorRole.Tool, AdvisorRole.Assistant, AdvisorRole.Tool, AdvisorRole.Tool, AdvisorRole.Assistant], roles);
        Assert.Equal(["c2", "c3"], conversation.Messages.Where(m => m.Role == AdvisorRole.Tool).Skip(1).Select(m => m.ToolCallId));
        Assert.Equal("result:get_inventory", conversation.Messages[3].Content);
    }

    [Fact]
    public async Task QuestionIsRedactedAndSystemPromptSentOnce()
    {
        var provider = new ScriptedProvider(new AdvisorCompletion("a", []), new AdvisorCompletion("b", []));
        var conversation = new AdvisorConversation(provider, new FakeModule());

        await conversation.AskAsync("Pfad C:\\Users\\max\\x");
        await conversation.AskAsync("noch was");

        Assert.Equal("[geschützt] Pfad C:\\Users\\max\\x", conversation.Messages[1].Content);
        Assert.Single(conversation.Messages, m => m.Role == AdvisorRole.System);
        Assert.Equal(2, provider.Seen.Count);
        Assert.Equal(["get_inventory", "get_program_details"], provider.SeenTools[0].Select(t => t.Name));
    }

    [Fact]
    public async Task ProviderKindDecidesWhichToolsTheModuleOffers()
    {
        var module = new FakeModule();
        var provider = new ScriptedProvider(Calls(("c1", "get_inventory", "{}")), new AdvisorCompletion("ok", [])) { KindValue = AdvisorProviderKind.External };

        await new AdvisorConversation(provider, module).AskAsync("?");

        Assert.Equal([AdvisorProviderKind.External], module.ToolKinds);
        Assert.Equal(AdvisorProviderKind.External, module.Invoked.Single().Kind);
    }

    [Fact]
    public async Task StopsAfterTheRoundLimitAndLeavesTheConversationAsBefore()
    {
        var endless = Enumerable.Range(0, 20).Select(i => Calls(($"c{i}", "get_inventory", "{}"))).ToArray();
        var provider = new ScriptedProvider([new AdvisorCompletion("erste Antwort", []), .. endless]);
        var module = new FakeModule();
        var conversation = new AdvisorConversation(provider, module);
        await conversation.AskAsync("erste Frage");
        var before = conversation.Messages.ToList();

        var ex = await Assert.ThrowsAsync<AdvisorException>(() => conversation.AskAsync("zweite Frage"));

        Assert.Equal("AdvisorToolRoundLimit", ex.Code);
        Assert.Equal(AdvisorConversation.DefaultMaxToolRounds, module.Invoked.Count);
        Assert.Equal(before, conversation.Messages);
    }

    [Fact]
    public async Task ProviderErrorLeavesNoHalfRound()
    {
        var provider = new ScriptedProvider(Calls(("c1", "get_inventory", "{}"))) { FailAfter = 1 };
        var conversation = new AdvisorConversation(provider, new FakeModule());

        await Assert.ThrowsAsync<AdvisorException>(() => conversation.AskAsync("?"));

        Assert.Empty(conversation.Messages);
    }

    [Fact]
    public async Task ConnectionTestPassesWhenTheModelCallsTheTool()
    {
        var provider = new ScriptedProvider(Calls(("t", "get_inventory", "{}"))) { ModelValue = "qwen3:8b", ModelsValue = ["qwen3:8b"] };
        var result = await new AdvisorService(new FakeModule(), _ => provider).TestConnectionAsync(Connection());

        Assert.Equal("AdvisorTestOk", result.Code);
        Assert.True(result.Ok && result.CanSave && !result.Warning);
        // Nur get_inventory angeboten, nichts ausgeführt und keine Inventardaten im Gespräch
        Assert.Equal(["get_inventory"], provider.SeenTools.Single().Select(t => t.Name));
        Assert.DoesNotContain(provider.Seen.Single(), m => m.Role == AdvisorRole.Tool);
        Assert.True(provider.Disposed);
    }

    [Fact]
    public async Task ConnectionTestWarnsButAllowsSavingWithoutToolCall()
    {
        var provider = new ScriptedProvider(new AdvisorCompletion("Es sind 42.", [])) { ModelValue = "m", ModelsValue = ["m"] };
        var result = await new AdvisorService(new FakeModule(), _ => provider).TestConnectionAsync(Connection());

        Assert.Equal("AdvisorTestNoToolCall", result.Code);
        Assert.True(result.Warning);
        Assert.True(result.CanSave);
    }

    [Fact]
    public async Task ConnectionTestWarnsWhenTheToolRequestFails()
    {
        var provider = new ScriptedProvider() { ModelValue = "m", ModelsValue = ["m"], FailAfter = 0 };
        var result = await new AdvisorService(new FakeModule(), _ => provider).TestConnectionAsync(Connection());

        Assert.Equal("AdvisorHttpError", result.Code);
        Assert.True(result.Warning && result.CanSave);
    }

    [Fact]
    public async Task ConnectionTestStopsOnMissingModelOrBadAddress()
    {
        var missing = await new AdvisorService(new FakeModule(), _ => new ScriptedProvider { ModelValue = "weg", ModelsValue = ["a", "b"] }).TestConnectionAsync(Connection());
        Assert.Equal("AdvisorTestModelMissing", missing.Code);
        Assert.False(missing.CanSave);
        Assert.Equal(["a", "b"], missing.Models);

        var choose = await new AdvisorService(new FakeModule(), _ => new ScriptedProvider { ModelValue = null, ModelsValue = ["a"] }).TestConnectionAsync(Connection());
        Assert.Equal("AdvisorTestChooseModel", choose.Code);
        Assert.True(choose.CanSave);

        var created = false;
        var module = new FakeModule { Endpoint = new AdvisorEndpointStatus(false, "Public", false, "AdvisorEndpointNotLocal", "öffentlich") };
        var bad = await new AdvisorService(module, _ => { created = true; return new ScriptedProvider(); }).TestConnectionAsync(Connection());
        Assert.Equal("AdvisorEndpointNotLocal", bad.Code);
        Assert.False(bad.CanSave);
        Assert.False(created);
    }

    [Fact]
    public async Task ConnectionTestPassesTheUnencryptedNote()
    {
        var module = new FakeModule { Endpoint = new AdvisorEndpointStatus(true, "Private", true, "AdvisorEndpointUnencrypted", "unverschlüsselt") };
        var provider = new ScriptedProvider(Calls(("t", "get_inventory", "{}"))) { ModelValue = "m", ModelsValue = ["m"] };

        var result = await new AdvisorService(module, _ => provider).TestConnectionAsync(Connection());

        Assert.Equal("unverschlüsselt", result.EndpointNote);
    }

    [Fact]
    public async Task ConversationNeedsTheAdvisorSwitchedOn()
    {
        var module = new FakeModule { ConnectionValue = Connection() with { Enabled = false } };
        var ex = await Assert.ThrowsAsync<AdvisorException>(() => new AdvisorService(module, _ => new ScriptedProvider()).StartConversationAsync());
        Assert.Equal("AdvisorDisabled", ex.Code);
    }

    private static AdvisorConnection Connection() => new(true, "Ollama", "http://localhost:11434/v1", "m", AdvisorProviderKind.Local, null);

    private static AdvisorCompletion Calls(params (string Id, string Name, string Args)[] calls) =>
        new(null, calls.Select(c => new AdvisorToolCall(c.Id, c.Name, c.Args)).ToList());

    private sealed class ScriptedProvider(params AdvisorCompletion[] script) : IAdvisorProvider
    {
        private int _next;

        public AdvisorProviderKind KindValue { get; init; } = AdvisorProviderKind.Local;

        public string? ModelValue { get; init; } = "m";

        public IReadOnlyList<string> ModelsValue { get; init; } = ["m"];

        /// <summary>Nach so vielen Antworten wirft der Anbieter AdvisorHttpError.</summary>
        public int FailAfter { get; init; } = int.MaxValue;

        public List<IReadOnlyList<AdvisorMessage>> Seen { get; } = [];

        public List<IReadOnlyList<AdvisorToolDefinition>> SeenTools { get; } = [];

        public bool Disposed { get; private set; }

        public string Id => "Scripted";

        public AdvisorProviderKind Kind => KindValue;

        public string? Model => ModelValue;

        public Task<IReadOnlyList<string>> ListModelsAsync(CancellationToken cancellationToken = default) => Task.FromResult(ModelsValue);

        public Task<AdvisorCompletion> CompleteAsync(IReadOnlyList<AdvisorMessage> messages, IReadOnlyList<AdvisorToolDefinition> tools, CancellationToken cancellationToken = default)
        {
            Seen.Add(messages.ToList());
            SeenTools.Add(tools);
            if (_next >= FailAfter)
            {
                throw new AdvisorException("AdvisorHttpError", 500);
            }
            return Task.FromResult(script[_next++]);
        }

        public void Dispose() => Disposed = true;
    }

    private sealed class FakeModule : IAdvisorModule
    {
        public List<(string Name, string Args, AdvisorProviderKind Kind)> Invoked { get; } = [];

        public List<AdvisorProviderKind> ToolKinds { get; } = [];

        public AdvisorEndpointStatus Endpoint { get; init; } = new(true, "Loopback", false, null, null);

        public AdvisorConnection ConnectionValue { get; init; } = Connection();

        public Task<AdvisorConnection> GetConnectionAsync(CancellationToken cancellationToken = default) => Task.FromResult(ConnectionValue);

        public Task<string> GetSystemPromptAsync(CancellationToken cancellationToken = default) => Task.FromResult("system");

        public Task<IReadOnlyList<AdvisorToolDefinition>> GetToolsAsync(AdvisorProviderKind kind, CancellationToken cancellationToken = default)
        {
            ToolKinds.Add(kind);
            return Task.FromResult<IReadOnlyList<AdvisorToolDefinition>>(
                [new("get_inventory", "Read", "Liste", "{}"), new("get_program_details", "Read", "Details", "{}")]);
        }

        public Task<AdvisorToolResult> InvokeToolAsync(string name, string argumentsJson, AdvisorProviderKind kind, CancellationToken cancellationToken = default)
        {
            Invoked.Add((name, argumentsJson, kind));
            var proposal = name.StartsWith("propose_", StringComparison.Ordinal) ? new PSObject() : null;
            return Task.FromResult(new AdvisorToolResult(name, true, null, "result:" + name, proposal));
        }

        public Task<string> ProtectTextAsync(string text, CancellationToken cancellationToken = default) => Task.FromResult("[geschützt] " + text);

        public Task<AdvisorEndpointStatus> CheckEndpointAsync(string endpoint, CancellationToken cancellationToken = default) => Task.FromResult(Endpoint);

        public Task<AdvisorDataPreview> GetDataPreviewAsync(int level, CancellationToken cancellationToken = default) =>
            Task.FromResult(new AdvisorDataPreview(level, true, "{}", null));
    }
}

/// <summary>Anbindung an das echte Modul; Einstellungen und App-Ordner liegen in einem Testverzeichnis.</summary>
public sealed class AdvisorModuleTests : IAsyncLifetime
{
    private readonly PowerShellHost _host = new();
    private readonly string _appData = Path.Combine(Path.GetTempPath(), "SoftwareverwaltungTests", Guid.NewGuid().ToString("N"));
    private AdvisorModule _module = null!;

    public async Task InitializeAsync()
    {
        await _host.InitializeAsync();
        Directory.CreateDirectory(_appData);
        // Gespeicherte Schlüssel des Benutzers bleiben außen vor: nur die Umgebungsvariable des Runspace zählt.
        var result = await _host.InvokeAsync(new PSCommand().AddScript("""
            param($Dir)
            & (Get-Module SoftwareInventory) {
                param($Dir)
                $script:TestAppData = $Dir
                function script:Get-AppDataDirectory { $script:TestAppData }
                function script:Get-SettingsPath { Join-Path $script:TestAppData 'settings.json' }
                $script:TestAdvisorKey = $null
                function script:Read-StoredSecret { param($Service) $null }
                function script:Read-EnvironmentSecret { param($Service) if ($Service -eq 'Advisor') { $script:TestAdvisorKey } }
            } $Dir
            Set-AdvisorContext -Rating @()
            """).AddParameter("Dir", _appData));
        Assert.Empty(result.Errors);
        _module = new AdvisorModule(_host);
    }

    public Task DisposeAsync()
    {
        _host.Dispose();
        Directory.Delete(_appData, recursive: true);
        return Task.CompletedTask;
    }

    [Fact]
    public async Task ConnectionComesFromSettingsWithPresetAddressAndKeyAsSecureString()
    {
        await Run("Set-InventorySetting -AdvisorPreset Ollama -AdvisorModel 'qwen3:8b' -AdvisorEnabled $true | Out-Null");
        await Run("& (Get-Module SoftwareInventory) { $script:TestAdvisorKey = 'sk-unsloth-abc' }");

        var connection = await _module.GetConnectionAsync();

        Assert.True(connection.Enabled);
        Assert.Equal("http://localhost:11434/v1", connection.Endpoint);
        Assert.Equal("qwen3:8b", connection.Model);
        Assert.Equal(AdvisorProviderKind.Local, connection.Kind);
        Assert.NotNull(connection.ApiKey);
        var pointer = Marshal.SecureStringToGlobalAllocUnicode(connection.ApiKey!);
        try
        {
            Assert.Equal("sk-unsloth-abc", Marshal.PtrToStringUni(pointer));
        }
        finally
        {
            Marshal.ZeroFreeGlobalAllocUnicode(pointer);
        }
    }

    [Fact]
    public async Task WithoutKeyTheConnectionHasNone()
    {
        Assert.Null((await _module.GetConnectionAsync()).ApiKey);
    }

    [Fact]
    public async Task ToolsAndResultsFollowTheShareLevelOfTheProviderKind()
    {
        Assert.Equal(6, (await _module.GetToolsAsync(AdvisorProviderKind.Local)).Count);
        await Run("Set-InventorySetting -AdvisorShareLevelExternal 0 | Out-Null");

        var external = await _module.GetToolsAsync(AdvisorProviderKind.External);
        Assert.Equal(["get_inventory"], external.Select(t => t.Name));
        var refused = await _module.InvokeToolAsync("get_program_details", """{"id":"p-0123456789ab"}""", AdvisorProviderKind.External);
        Assert.False(refused.Ok);
        Assert.Equal("ShareLevelTooLow", refused.Code);

        var local = await _module.InvokeToolAsync("get_inventory", "{}", AdvisorProviderKind.Local);
        Assert.True(local.Ok);
        Assert.Contains("\"share_level\":3", local.Content);
        Assert.Contains("\"programs_in_scan\":0", local.Content);
    }

    [Fact]
    public async Task UserTextIsRedactedByTheModule()
    {
        var text = await _module.ProtectTextAsync($"Ich bin {Environment.UserName} auf {Environment.MachineName}");

        Assert.DoesNotContain(Environment.UserName, text, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("%USERNAME%", text);
        Assert.Contains("%COMPUTERNAME%", text);
    }

    [Fact]
    public async Task EndpointCheckComesFromTheModule()
    {
        var loopback = await _module.CheckEndpointAsync("http://127.0.0.1:11434/v1");
        Assert.True(loopback.Ok);
        Assert.Equal("Loopback", loopback.Network);

        var privateHttp = await _module.CheckEndpointAsync("http://192.168.1.20:11434/v1");
        Assert.True(privateHttp.Unencrypted);
        Assert.Equal("AdvisorEndpointUnencrypted", privateHttp.Code);
        Assert.False(string.IsNullOrEmpty(privateHttp.Message));

        var pub = await _module.CheckEndpointAsync("https://8.8.8.8/v1");
        Assert.False(pub.Ok);
        Assert.Equal("AdvisorEndpointNotLocal", pub.Code);
    }

    [Fact]
    public async Task ConversationRunsRealToolsThroughTheModule()
    {
        var provider = new OpenAiCompatibleProvider(
            new AdvisorConnection(true, "Ollama", "http://localhost:11434/v1", "m", AdvisorProviderKind.Local, null),
            new ReplayHandler(
                """{"choices":[{"message":{"content":null,"tool_calls":[{"id":"c1","type":"function","function":{"name":"get_inventory","arguments":"{}"}}]}}]}""",
                """{"choices":[{"message":{"content":"Keine Programme im Scan."}}]}"""));
        var conversation = new AdvisorConversation(provider, _module);

        var reply = await conversation.AskAsync("Wie viele Programme?");

        Assert.Equal("Keine Programme im Scan.", reply.Text);
        var tool = conversation.Messages.Single(m => m.Role == AdvisorRole.Tool);
        Assert.Equal("c1", tool.ToolCallId);
        Assert.Contains("\"programs_in_scan\":0", tool.Content);
    }

    private async Task Run(string script)
    {
        var result = await _host.InvokeAsync(new PSCommand().AddScript(script));
        Assert.Empty(result.Errors);
    }

    private sealed class ReplayHandler(params string[] answers) : System.Net.Http.HttpMessageHandler
    {
        private int _next;

        protected override Task<System.Net.Http.HttpResponseMessage> SendAsync(System.Net.Http.HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(new System.Net.Http.HttpResponseMessage(HttpStatusCode.OK) { Content = new System.Net.Http.StringContent(answers[_next++]) });
    }
}
