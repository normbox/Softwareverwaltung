using Softwareverwaltung.App.Advisor;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;
using Softwareverwaltung.App.ViewModels;
using static Softwareverwaltung.App.Tests.TestHelpers;
using FakeSettings = Softwareverwaltung.App.Tests.SettingsViewModelTests.FakeSettings;

namespace Softwareverwaltung.App.Tests;

/// <summary>Chat-Seitenleiste des KI-Beraters mit vorgegebenem Gespräch; es wird nie ein Server gefragt.</summary>
public sealed class AdvisorChatTests
{
    private static readonly SoftwareItem Tool = new() { Name = "7-Zip", Rating = Rating.Yellow, UpdateAvailable = true };

    private static AppSettings Enabled() => new()
    {
        Usage = "Private", AdvisorEnabled = true, AdvisorPreset = "Ollama", AdvisorEndpoint = "http://localhost:11434/v1", AdvisorModel = "m", AdvisorShareLevelLocal = 3,
    };

    private sealed record Setup(AdvisorChatViewModel Chat, MainViewModel Programs, SettingsViewModel Settings, FakeSettings Store, FakeChatService Service, ShellViewModel Shell, MemoryAppUiStore Ui);

    private static async Task<Setup> CreateAsync(AppSettings? saved = null, bool scan = true, FakeChatService? service = null)
    {
        var ui = new MemoryAppUiStore();
        var programs = new MainViewModel(new ScanOnlyInventory { Items = [Tool] }, ui: ui);
        var store = new FakeSettings { Saved = saved ?? Enabled() };
        var settings = new SettingsViewModel(store);
        service ??= new FakeChatService();
        var chat = new AdvisorChatViewModel(service, programs, settings, ui);
        var shell = new ShellViewModel(programs, settings, chat);
        await shell.InitializeAsync();
        if (scan)
        {
            await programs.ScanCommand.ExecuteAsync(null);
        }
        return new Setup(chat, programs, settings, store, service, shell, ui);
    }

    [Fact]
    public void DisabledAdvisorShowsTheHintAndLinksToTheSettings() => RunOnDispatcher(async () =>
    {
        var s = await CreateAsync(Enabled() with { AdvisorEnabled = false });
        s.Chat.Question = "Hallo";

        Assert.True(s.Chat.ShowDisabledState);
        Assert.False(s.Chat.CanType);
        Assert.False(s.Chat.SendCommand.CanExecute(null));

        s.Chat.OpenSettingsCommand.Execute(null);
        Assert.Equal(ShellViewModel.SettingsTab, s.Shell.SelectedTab);
    });

    [Fact]
    public void WithoutScanNothingCanBeAsked() => RunOnDispatcher(async () =>
    {
        var s = await CreateAsync(scan: false);
        s.Chat.Question = "Was ist rot?";

        Assert.True(s.Chat.ShowNoScanState);
        Assert.False(s.Chat.SendCommand.CanExecute(null));

        await s.Programs.ScanCommand.ExecuteAsync(null);
        Assert.True(s.Chat.ShowEmptyConversation);
        Assert.True(s.Chat.SendCommand.CanExecute(null));
    });

    [Fact]
    public void AnswerIsPlainTextWithTheToolSummaryAndOneSessionPerConversation() => RunOnDispatcher(async () =>
    {
        var s = await CreateAsync();
        s.Service.Replies.Enqueue(new AdvisorReply("## Ergebnis\n**7-Zip** zuerst, siehe [Hinweis](https://example.org).", [], 2, ["get_inventory", "get_program_details", "get_program_details"]));
        s.Service.Replies.Enqueue(new AdvisorReply("Gern.", [], 0, []));

        s.Chat.Question = "  Was zuerst?  ";
        await s.Chat.SendCommand.ExecuteAsync(null);
        s.Chat.Question = "Danke";
        await s.Chat.SendCommand.ExecuteAsync(null);

        Assert.Equal(1, s.Service.Started);
        Assert.Equal(["Was zuerst?", "Danke"], s.Service.Sessions.Single().Questions);
        Assert.Equal([AdvisorChatEntryKind.User, AdvisorChatEntryKind.Assistant, AdvisorChatEntryKind.User, AdvisorChatEntryKind.Assistant], s.Chat.Entries.Select(e => e.Kind));
        var answer = s.Chat.Entries[1];
        Assert.Equal("Ergebnis\n7-Zip zuerst, siehe Hinweis (https://example.org).", answer.Text);
        Assert.Equal("Abgefragt: Programmliste, Programmdetails (2×)", answer.Detail);
        Assert.Equal("Ohne Datenabfrage beantwortet.", s.Chat.Entries[3].Detail);
        Assert.Equal("", s.Chat.Question);
    });

    [Fact]
    public void WhileTheAdvisorAnswersScanAndActionsAreBlocked() => RunOnDispatcher(async () =>
    {
        var s = await CreateAsync();
        var hold = new TaskCompletionSource<AdvisorReply>();
        s.Service.Pending = hold;
        s.Chat.Question = "Was zuerst?";

        var running = s.Chat.SendCommand.ExecuteAsync(null);

        Assert.True(s.Chat.IsAnswering);
        Assert.True(s.Programs.IsAdvisorBusy);
        Assert.False(s.Programs.ScanCommand.CanExecute(null));
        Assert.NotNull(s.Chat.StateText);

        hold.SetResult(new AdvisorReply("ok", [], 0, []));
        await running;

        Assert.False(s.Programs.IsAdvisorBusy);
        Assert.True(s.Programs.ScanCommand.CanExecute(null));
    });

    [Fact]
    public void WhileAScanRunsNothingCanBeAsked() => RunOnDispatcher(async () =>
    {
        var s = await CreateAsync();
        s.Chat.Question = "Was zuerst?";

        s.Programs.IsBusy = true;
        Assert.False(s.Chat.SendCommand.CanExecute(null));
        Assert.Equal("Ein Scan oder eine Aktion läuft. Danach kann wieder gefragt werden.", s.Chat.StateText);

        s.Programs.IsBusy = false;
        Assert.True(s.Chat.SendCommand.CanExecute(null));
        Assert.Null(s.Chat.StateText);
    });

    [Fact]
    public void CancelStopsTheAnswerAndPutsTheQuestionBack() => RunOnDispatcher(async () =>
    {
        var s = await CreateAsync();
        s.Service.WaitForCancel = true;
        s.Chat.Question = "Was zuerst?";

        var running = s.Chat.SendCommand.ExecuteAsync(null);
        s.Chat.SendCancelCommand.Execute(null);
        await running;

        Assert.Equal(AdvisorChatEntryKind.Info, s.Chat.Entries.Last().Kind);
        Assert.Equal("Was zuerst?", s.Chat.Question);
        Assert.False(s.Chat.IsAnswering);
        Assert.False(s.Programs.IsAdvisorBusy);
    });

    [Fact]
    public void ErrorsAreShownAndTheQuestionComesBack() => RunOnDispatcher(async () =>
    {
        var s = await CreateAsync();
        s.Service.Failure = new AdvisorException("AdvisorToolRoundLimit", 8);
        s.Chat.Question = "Was zuerst?";

        await s.Chat.SendCommand.ExecuteAsync(null);

        var error = s.Chat.Entries.Last();
        Assert.Equal(AdvisorChatEntryKind.Error, error.Kind);
        Assert.Contains("8 Runden", error.Text);
        Assert.Equal("Was zuerst?", s.Chat.Question);
    });

    [Fact]
    public void AiNoticeAreaStaysAvailableAfterErrorsAndANewConversation() => RunOnDispatcher(async () =>
    {
        // Die Zeile steht im Bereich, der an CanType hängt (siehe AppTextTests).
        var s = await CreateAsync();
        Assert.True(s.Chat.CanType);

        s.Service.Failure = new AdvisorException("AdvisorToolRoundLimit", 8);
        s.Chat.Question = "Was zuerst?";
        await s.Chat.SendCommand.ExecuteAsync(null);
        Assert.True(s.Chat.CanType);

        s.Chat.NewConversationCommand.Execute(null);
        Assert.Empty(s.Chat.Entries);
        Assert.True(s.Chat.CanType);
    });

    [Fact]
    public void NewConversationDropsTheSession() => RunOnDispatcher(async () =>
    {
        var s = await CreateAsync();
        Assert.False(s.Chat.NewConversationCommand.CanExecute(null));
        s.Chat.Question = "Eins";
        await s.Chat.SendCommand.ExecuteAsync(null);

        s.Chat.NewConversationCommand.Execute(null);

        Assert.Empty(s.Chat.Entries);
        Assert.True(s.Service.Sessions[0].Disposed);
        s.Chat.Question = "Zwei";
        await s.Chat.SendCommand.ExecuteAsync(null);
        Assert.Equal(2, s.Service.Started);
        Assert.Equal(["Zwei"], s.Service.Sessions[1].Questions);
    });

    [Fact]
    public void SavedAdvisorChangesStartANewConversation() => RunOnDispatcher(async () =>
    {
        var s = await CreateAsync();
        s.Chat.Question = "Eins";
        await s.Chat.SendCommand.ExecuteAsync(null);

        // Andere Einstellung ohne Bezug zum Berater: Gespräch bleibt.
        s.Settings.LogRetentionDays += 1;
        await s.Settings.SaveCommand.ExecuteAsync(null);
        Assert.Equal(2, s.Chat.Entries.Count);
        Assert.False(s.Service.Sessions[0].Disposed);

        s.Settings.AdvisorModel = "anderes";
        await s.Settings.SaveCommand.ExecuteAsync(null);

        Assert.True(s.Service.Sessions[0].Disposed);
        Assert.Equal(AdvisorChatEntryKind.Info, s.Chat.Entries.Single().Kind);
    });

    [Fact]
    public void PanelStateIsRememberedWithoutLosingTheDetailsWidth() => RunOnDispatcher(async () =>
    {
        var s = await CreateAsync();
        s.Programs.DetailsWidthFraction = 0.5;

        s.Chat.ToggleCommand.Execute(null);
        s.Chat.PanelWidth = 5000;

        Assert.True(s.Ui.Current.AdvisorPanelOpen);
        Assert.Equal(AppUiSettings.MaxAdvisorPanelWidth, s.Ui.Current.AdvisorPanelWidth);
        Assert.Equal(0.5, s.Ui.Current.DetailsWidthFraction);

        var again = new AdvisorChatViewModel(s.Service, s.Programs, s.Settings, s.Ui);
        Assert.True(again.IsOpen);
        Assert.Equal(AppUiSettings.MaxAdvisorPanelWidth, again.PanelWidth);
    });

    [Theory]
    [InlineData("<think>überlege</think>Antwort", "Antwort")]
    [InlineData("# Titel\n\n\n\nText", "Titel\n\nText")]
    [InlineData("- eins\n* zwei\n  + drei", "• eins\n• zwei\n  • drei")]
    [InlineData("```powershell\nwinget upgrade\n```", "winget upgrade")]
    [InlineData("Nutze `winget` und __das__", "Nutze winget und das")]
    [InlineData("[https://x.org](https://x.org)", "https://x.org")]
    public void ModelTextBecomesPlainText(string input, string expected) =>
        Assert.Equal(expected, AdvisorPlainText.From(input));

    private sealed class FakeChatService : IAdvisorChatService
    {
        public Queue<AdvisorReply> Replies { get; } = new();

        public TaskCompletionSource<AdvisorReply>? Pending { get; set; }

        public bool WaitForCancel { get; set; }

        public Exception? Failure { get; set; }

        public int Started { get; private set; }

        public List<FakeSession> Sessions { get; } = [];

        public Task<IAdvisorChatSession> StartSessionAsync(CancellationToken cancellationToken = default)
        {
            Started++;
            var session = new FakeSession(this);
            Sessions.Add(session);
            return Task.FromResult<IAdvisorChatSession>(session);
        }
    }

    private sealed class FakeSession(FakeChatService service) : IAdvisorChatSession
    {
        public List<string> Questions { get; } = [];

        public bool Disposed { get; private set; }

        public async Task<AdvisorReply> AskAsync(string question, CancellationToken cancellationToken = default)
        {
            Questions.Add(question);
            if (service.Failure is not null)
            {
                throw service.Failure;
            }
            if (service.WaitForCancel)
            {
                await Task.Delay(Timeout.Infinite, cancellationToken);
            }
            if (service.Pending is not null)
            {
                return await service.Pending.Task;
            }
            return service.Replies.Count > 0 ? service.Replies.Dequeue() : new AdvisorReply("ok", [], 0, []);
        }

        public void Dispose() => Disposed = true;
    }

    private sealed class ScanOnlyInventory : IInventoryService
    {
        public IReadOnlyList<SoftwareItem> Items { get; init; } = [];

        public Task<IReadOnlyList<string>> InitializeAsync(CancellationToken cancellationToken = default) => Task.FromResult<IReadOnlyList<string>>([]);

        public Task<WingetStatus> GetWingetStatusAsync(CancellationToken cancellationToken = default) => Task.FromResult(new WingetStatus(true, null, null));

        public Task<RefreshEstimate?> GetRefreshEstimateAsync(IReadOnlyList<System.Management.Automation.PSObject> sources, CancellationToken cancellationToken = default) =>
            Task.FromResult<RefreshEstimate?>(null);

        public Task<ScanResult> ScanAsync(IProgress<string>? progress = null, CancellationToken cancellationToken = default, bool refresh = false) =>
            Task.FromResult(new ScanResult(Items, [], []));

        public Task<InstallLocationInfo?> ResolveInstallLocationAsync(System.Management.Automation.PSObject source, CancellationToken cancellationToken = default) =>
            Task.FromResult<InstallLocationInfo?>(null);
    }
}
