using Softwareverwaltung.App.Advisor;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.ViewModels;
using FakeSettings = Softwareverwaltung.App.Tests.SettingsViewModelTests.FakeSettings;

namespace Softwareverwaltung.App.Tests;

/// <summary>Abschnitt „KI-Berater“ der Einstellungsseite mit vorgegebenen Diensten.</summary>
public sealed class SettingsAdvisorTests
{
    private static AppSettings Saved(Func<AppSettings, AppSettings>? change = null)
    {
        var settings = new AppSettings { Usage = "Private", AdvisorPreset = "Ollama", AdvisorEndpoint = "http://localhost:11434/v1", AdvisorShareLevelLocal = 3 };
        return change is null ? settings : change(settings);
    }

    private static async Task<(SettingsViewModel Vm, FakeSettings Settings, FakeAdvisor Advisor)> LoadAsync(AppSettings? saved = null)
    {
        var settings = new FakeSettings { Saved = saved ?? Saved() };
        var advisor = new FakeAdvisor();
        var vm = new SettingsViewModel(settings, advisor: advisor);
        await vm.LoadAsync();
        return (vm, settings, advisor);
    }

    [Fact]
    public async Task LoadsTheAdvisorValuesWithoutDefaultModel()
    {
        var (vm, _, _) = await LoadAsync();

        Assert.False(vm.IsDirty);
        Assert.False(vm.AdvisorEnabled);
        Assert.Equal("Ollama", vm.AdvisorPreset);
        Assert.Equal("http://localhost:11434/v1", vm.AdvisorEndpoint);
        Assert.Null(vm.AdvisorModel);
        Assert.Equal(3, vm.AdvisorShareLevelLocal);
        Assert.True(vm.ShareLevels.Single(l => l.Level == 3).IsSelected);
        Assert.Equal(1, vm.ShareLevels.Count(l => l.IsSelected));
        Assert.Equal(3, vm.AdvisorPresets.Count);
    }

    [Fact]
    public async Task LoadingModelsFillsTheListButChoosesNone()
    {
        var (vm, _, advisor) = await LoadAsync();
        advisor.Models = new AdvisorModelList(["llama3.2", "qwen3:8b"], "unverschlüsselt");

        await vm.LoadModelsCommand.ExecuteAsync(null);

        Assert.Equal(["llama3.2", "qwen3:8b"], vm.AdvisorModels);
        Assert.Null(vm.AdvisorModel);
        Assert.False(vm.IsDirty);
        Assert.Equal("unverschlüsselt", vm.AdvisorEndpointNote);
        Assert.Equal("Informational", vm.AdvisorResultSeverity);
        Assert.Equal(new AdvisorDraft("Ollama", "http://localhost:11434/v1", null), advisor.LastDraft);
    }

    [Fact]
    public async Task ModelListErrorsAreShownAsError()
    {
        var (vm, _, advisor) = await LoadAsync();
        advisor.ModelsFailure = new AdvisorException("AdvisorServerUnreachable", "localhost:11434");

        await vm.LoadModelsCommand.ExecuteAsync(null);

        Assert.Equal("Error", vm.AdvisorResultSeverity);
        Assert.Contains("localhost:11434", vm.AdvisorResultText);
        Assert.False(vm.IsAdvisorBusy);
    }

    [Fact]
    public async Task PresetPrefillsTheAddressOnlyWhenItHasOne()
    {
        var (vm, _, _) = await LoadAsync();

        vm.AdvisorPreset = "Unsloth";
        Assert.Equal("http://localhost:8888/v1", vm.AdvisorEndpoint);
        Assert.True(vm.AdvisorPresetNeedsKey);
        Assert.Equal("Braucht einen Schlüssel.", vm.AdvisorPresetNote);

        vm.AdvisorPreset = "Custom";
        Assert.Equal("http://localhost:8888/v1", vm.AdvisorEndpoint);
        Assert.True(vm.IsDirty);
    }

    [Fact]
    public async Task SavePassesTheSavedStateSoUnchangedValuesStayOut()
    {
        var (vm, settings, _) = await LoadAsync();
        var before = settings.Saved;
        vm.AdvisorEndpoint = " http://192.168.1.20:11434/v1 ";
        vm.AdvisorModel = "qwen3:8b";
        vm.AdvisorEnabled = true;

        await vm.SaveCommand.ExecuteAsync(null);

        Assert.Same(before, settings.LastPrevious);
        Assert.Equal("http://192.168.1.20:11434/v1", settings.Saved.AdvisorEndpoint);
        Assert.Equal("qwen3:8b", settings.Saved.AdvisorModel);
        Assert.True(settings.Saved.AdvisorEnabled);
        Assert.False(vm.IsDirty);
    }

    [Fact]
    public async Task ChoosingLevelFourShowsTheHintAndMarksDirty()
    {
        var (vm, _, _) = await LoadAsync();

        vm.ShareLevels.Single(l => l.Level == 4).IsSelected = true;

        Assert.Equal(4, vm.AdvisorShareLevelLocal);
        Assert.True(vm.ShowLevel4Hint);
        Assert.True(vm.IsDirty);
        Assert.Equal([4], vm.ShareLevels.Where(l => l.IsSelected).Select(l => l.Level));

        vm.DiscardCommand.Execute(null);
        Assert.Equal(3, vm.AdvisorShareLevelLocal);
        Assert.True(vm.ShareLevels.Single(l => l.Level == 3).IsSelected);
    }

    [Fact]
    public async Task NoticeShowsInMainOnlyWhenTheAdvisorIsOnAndIsSavedOnlyWithTheCheckbox()
    {
        var (off, _, _) = await LoadAsync(Saved(s => s with { AdvisorShareLevelLocal = 2, AdvisorShareLevelNoticePending = true }));
        Assert.True(off.ShowShareLevelNotice);
        Assert.False(off.ShowShareLevelNoticeInMain);

        var (on, settings, _) = await LoadAsync(Saved(s => s with { AdvisorEnabled = true, AdvisorModel = "m", AdvisorShareLevelLocal = 2, AdvisorShareLevelNoticePending = true }));
        Assert.True(on.ShowShareLevelNoticeInMain);
        Assert.False(on.DontShowShareLevelNoticeAgain);

        // ✕ ohne Haken: nur für diese Sitzung, nichts gespeichert
        await on.DismissShareLevelNoticeCommand.ExecuteAsync(null);
        Assert.DoesNotContain("DismissNotice", settings.Calls);
        Assert.False(on.ShowShareLevelNotice);
        Assert.False(on.ShowShareLevelNoticeInMain);
        Assert.False(on.IsDirty);

        // Späteres Speichern einer anderen Einstellung holt ihn in dieser Sitzung nicht zurück
        on.LogRetentionDays += 1;
        await on.SaveCommand.ExecuteAsync(null);
        Assert.False(on.ShowShareLevelNotice);

        // Neustart (neues ViewModel): wieder da; mit Haken dauerhaft weg
        var (next, nextSettings, _) = await LoadAsync(settings.Saved);
        Assert.True(next.ShowShareLevelNotice);
        next.DontShowShareLevelNoticeAgain = true;
        await next.DismissShareLevelNoticeCommand.ExecuteAsync(null);
        Assert.Contains("DismissNotice", nextSettings.Calls);
        Assert.False(next.ShowShareLevelNotice);
        Assert.False(nextSettings.Saved.AdvisorShareLevelNoticePending);
    }

    [Theory]
    [InlineData(true, false, "Success")]
    [InlineData(false, true, "Warning")]
    [InlineData(false, false, "Error")]
    public async Task ConnectionTestUsesUnsavedValuesAndShowsTheOutcome(bool ok, bool warning, string severity)
    {
        var (vm, _, advisor) = await LoadAsync();
        advisor.TestResult = new AdvisorConnectionTestResult("X", ok, warning, ok || warning, ["m"], "Ergebnis", null);
        vm.AdvisorEndpoint = "http://10.0.0.5:1234/v1";
        vm.AdvisorModel = "m";

        await vm.TestConnectionCommand.ExecuteAsync(null);

        Assert.Equal(new AdvisorDraft("Ollama", "http://10.0.0.5:1234/v1", "m"), advisor.LastDraft);
        Assert.Equal(severity, vm.AdvisorResultSeverity);
        Assert.Equal("Ergebnis", vm.AdvisorResultText);
        Assert.Equal(["m"], vm.AdvisorModels);
        Assert.Equal("m", vm.AdvisorModel);
    }

    [Fact]
    public async Task WithoutAddressThereIsNothingToTest()
    {
        var (vm, _, _) = await LoadAsync(Saved(s => s with { AdvisorPreset = "Custom", AdvisorEndpoint = null }));

        Assert.False(vm.TestConnectionCommand.CanExecute(null));
        Assert.False(vm.LoadModelsCommand.CanExecute(null));
        vm.AdvisorEndpoint = "http://localhost:1/v1";
        Assert.True(vm.TestConnectionCommand.CanExecute(null));
    }

    [Fact]
    public async Task PreviewFollowsTheChosenLevelAndExplainsMissingScan()
    {
        var (vm, _, advisor) = await LoadAsync();
        advisor.HasScanData = false;

        vm.IsPreviewOpen = true;
        await WaitFor(() => vm.PreviewHint is not null);
        Assert.Contains("Scan", vm.PreviewHint);
        Assert.Null(vm.PreviewText);

        advisor.HasScanData = true;
        vm.ShareLevels.Single(l => l.Level == 1).IsSelected = true;
        await WaitFor(() => vm.PreviewText?.Contains("get_program_details") == true);

        Assert.Equal(1, advisor.PreviewLevels.Last());
        Assert.Contains("get_inventory", vm.PreviewText);
        Assert.Contains("\"share_level\": 1", vm.PreviewText);
        Assert.Null(vm.PreviewHint);
    }

    [Fact]
    public async Task AdvisorButtonsAreUsableRightAfterLoading()
    {
        var (vm, _, _) = await LoadAsync();

        Assert.True(vm.LoadModelsCommand.CanExecute(null));
        Assert.True(vm.TestConnectionCommand.CanExecute(null));
    }

    [Fact]
    public async Task NoticeCloseButtonIsUsableRightAfterLoading()
    {
        // Fehler aus der Praxis: IsLoaded wurde gesetzt, solange IsBusy noch wahr war; danach blieb der Knopf grau.
        var settings = new FakeSettings { Saved = Saved(s => s with { AdvisorShareLevelLocal = 2, AdvisorShareLevelNoticePending = true }) };
        var vm = new SettingsViewModel(settings, advisor: new FakeAdvisor());
        // WPF fragt CanExecute nur bei CanExecuteChanged ab und merkt sich das Ergebnis; maßgeblich ist also
        // der Zustand beim letzten Ereignis, nicht eine spätere direkte Abfrage.
        var seen = new List<bool>();
        vm.DismissShareLevelNoticeCommand.CanExecuteChanged += (_, _) => seen.Add(vm.DismissShareLevelNoticeCommand.CanExecute(null));

        await vm.LoadAsync();

        Assert.True(vm.ShowShareLevelNotice);
        Assert.NotEmpty(seen);
        Assert.True(seen[^1]);
    }

    [Fact]
    public async Task AdvisorKeyStatusIsLoadedWithTheOthers()
    {
        var (vm, _, _) = await LoadAsync();
        Assert.Equal("Advisor", vm.AdvisorCredential.Service);
        Assert.False(string.IsNullOrEmpty(vm.AdvisorCredential.StatusText));
    }

    private static async Task WaitFor(Func<bool> condition)
    {
        for (var i = 0; i < 100 && !condition(); i++)
        {
            await Task.Delay(10);
        }
        Assert.True(condition());
    }

    private sealed class FakeAdvisor : IAdvisorService
    {
        public AdvisorModelList Models { get; set; } = new([], null);

        public Exception? ModelsFailure { get; set; }

        public AdvisorConnectionTestResult TestResult { get; set; } = new("AdvisorTestOk", true, false, true, [], "ok", null);

        public bool HasScanData { get; set; } = true;

        public AdvisorDraft? LastDraft { get; private set; }

        public List<int> PreviewLevels { get; } = [];

        public Task<AdvisorModelList> ListModelsAsync(AdvisorDraft draft, CancellationToken cancellationToken = default)
        {
            LastDraft = draft;
            return ModelsFailure is null ? Task.FromResult(Models) : Task.FromException<AdvisorModelList>(ModelsFailure);
        }

        public Task<AdvisorConnectionTestResult> TestConnectionAsync(AdvisorDraft draft, CancellationToken cancellationToken = default)
        {
            LastDraft = draft;
            return Task.FromResult(TestResult);
        }

        public Task<AdvisorDataPreview> GetPreviewAsync(int level, CancellationToken cancellationToken = default)
        {
            PreviewLevels.Add(level);
            return Task.FromResult(new AdvisorDataPreview(level, HasScanData,
                $$"""{"share_level":{{level}},"programs":[{"id":"p-0123456789ab","name":"7-Zip"}]}""",
                HasScanData ? """{"name":"7-Zip"}""" : null));
        }
    }
}
