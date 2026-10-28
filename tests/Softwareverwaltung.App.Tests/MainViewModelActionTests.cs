using System.Management.Automation;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;
using Softwareverwaltung.App.ViewModels;
using static Softwareverwaltung.App.Tests.TestHelpers;

namespace Softwareverwaltung.App.Tests;

public sealed class MainViewModelActionTests
{
    private static readonly SoftwareItem Tool = new()
    {
        Name = "Contoso Tool", InstalledVersion = "2.1", LatestVersion = "3.0", UpdateAvailable = true, Rating = Rating.Yellow,
        Source = Ps(("Name", "Contoso Tool")),
    };

    private static ActionOutcome Planned(string action, string command = "winget upgrade --id Contoso.Tool", bool elevated = false) =>
        new() { Action = action, Name = "Contoso Tool", Result = "Planned", CommandLine = command, Elevated = elevated, RestorePoint = "NotRequested" };

    private static async Task<(MainViewModel Vm, FakeActions Actions, FakeConfirmation Confirm)> CreateAsync(FakeActions? actions = null, bool confirm = true, WingetStatus? winget = null)
    {
        actions ??= new FakeActions();
        var confirmation = new FakeConfirmation { Answer = confirm };
        var vm = new MainViewModel(new FakeInventory { Items = [Tool], Winget = winget ?? new WingetStatus(true, null, null) }, actions, confirmation);
        await vm.InitializeAsync();
        return (vm, actions, confirmation);
    }

    [Fact]
    public void UpdateShowsPlanRunsExactlyTheConfirmedCommandAndRechecksTheRow() => RunOnDispatcher(async () =>
    {
        var updated = Tool with { InstalledVersion = "3.0", UpdateAvailable = false, Rating = Rating.Green };
        var actions = new FakeActions
        {
            Plan = Planned("Update"),
            Outcome = new ActionOutcome { Action = "Update", Name = "Contoso Tool", Result = "Succeeded", Message = "Aktualisiert." },
            Recheck = updated,
        };
        var (vm, _, confirm) = await CreateAsync(actions);

        await vm.UpdateCommand.ExecuteAsync(Tool);

        Assert.Equal("winget upgrade --id Contoso.Tool", Assert.Single(confirm.Shown).CommandLine);
        // Nach der Aktion: erst die Online-Ergebnisse des Programms verwerfen, dann neu prüfen.
        Assert.Equal(["Plan:Update:Auto", "Execute:Update:Auto:winget upgrade --id Contoso.Tool", "ClearCache", "Recheck"], actions.Calls);
        Assert.Equal("Erfolgreich", vm.LastOutcome!.ResultText);
        Assert.Same(updated, Assert.Single(vm.Items));
        Assert.False(vm.IsBusy);
    });

    [Fact]
    public void DeclinedConfirmationRunsNothing() => RunOnDispatcher(async () =>
    {
        var (vm, actions, _) = await CreateAsync(new FakeActions { Plan = Planned("Uninstall") }, confirm: false);

        await vm.UninstallCommand.ExecuteAsync(Tool);

        Assert.Equal(["Plan:Uninstall:Auto"], actions.Calls);
        Assert.Null(vm.LastOutcome);
        Assert.Contains("nichts ausgeführt", vm.StatusText);
        Assert.Single(vm.Items);
    });

    [Fact]
    public void NonExecutablePlanIsShownWithoutDialog() => RunOnDispatcher(async () =>
    {
        var manual = new ActionOutcome
        {
            Action = "Update", Name = "Contoso Tool", Result = "ManualUpdateRequired", Message = "Kein winget-Paket bekannt.",
            VendorUrl = new Uri("https://contoso.example/download"),
        };
        var (vm, actions, confirm) = await CreateAsync(new FakeActions { Plan = manual });

        await vm.UpdateCommand.ExecuteAsync(Tool);

        Assert.Empty(confirm.Shown);
        Assert.Equal(["Plan:Update:Auto"], actions.Calls);
        Assert.Equal(new Uri("https://contoso.example/download"), vm.LastOutcome!.VendorUrl);
        Assert.Equal("Update von Hand nötig", vm.LastOutcome.ResultText);
    });

    [Fact]
    public void UninstalledProgramDisappearsFromTheList() => RunOnDispatcher(async () =>
    {
        var actions = new FakeActions
        {
            Plan = Planned("Uninstall", "msiexec.exe /x {GUID} /qn", elevated: true),
            Outcome = new ActionOutcome { Action = "Uninstall", Name = "Contoso Tool", Result = "Succeeded" },
            Recheck = null,
        };
        var (vm, _, confirm) = await CreateAsync(actions);

        await vm.UninstallCommand.ExecuteAsync(Tool);

        Assert.True(confirm.Shown[0].Elevated);
        Assert.Empty(vm.Items);
        Assert.Contains("nicht mehr installiert", vm.StatusText);
    });

    [Fact]
    public void OffersNextMethodOnlyAsNewConfirmedAttempt() => RunOnDispatcher(async () =>
    {
        var actions = new FakeActions
        {
            Plan = Planned("Uninstall", "winget uninstall --id Contoso.Tool"),
            Outcome = new ActionOutcome { Action = "Uninstall", Name = "Contoso Tool", Result = "NotVerified", NextMethod = "Msi" },
            Recheck = Tool,
        };
        var (vm, _, confirm) = await CreateAsync(actions);

        await vm.UninstallCommand.ExecuteAsync(Tool);
        Assert.True(vm.CanRetryWithNextMethod);

        actions.Plan = Planned("Uninstall", "msiexec.exe /x {GUID} /qn");
        actions.Outcome = new ActionOutcome { Action = "Uninstall", Name = "Contoso Tool", Result = "Succeeded" };
        actions.Recheck = null;
        await vm.RetryWithNextMethodCommand.ExecuteAsync(null);

        Assert.Equal(2, confirm.Shown.Count);
        Assert.Contains("Plan:Uninstall:Msi", actions.Calls);
        Assert.Contains("Execute:Uninstall:Msi:msiexec.exe /x {GUID} /qn", actions.Calls);
        Assert.False(vm.CanRetryWithNextMethod);
    });

    [Fact]
    public void ShowsErrorsAsFailedOutcome() => RunOnDispatcher(async () =>
    {
        var (vm, _, _) = await CreateAsync(new FakeActions { PlanFailure = new InvalidOperationException("Modul kaputt") });

        await vm.UpdateCommand.ExecuteAsync(Tool);

        Assert.Equal("Failed", vm.LastOutcome!.Result);
        Assert.Equal("Modul kaputt", vm.LastOutcome.Message);
        Assert.False(vm.IsBusy);
    });

    [Fact]
    public void WingetNoticeOffersInstallAndDisappearsAfterSuccess() => RunOnDispatcher(async () =>
    {
        var actions = new FakeActions
        {
            Plan = Planned("InstallWinget", "Repair-WinGetPackageManager -Latest"),
            Outcome = new ActionOutcome { Action = "InstallWinget", Name = "winget (App Installer)", Result = "Succeeded" },
        };
        var (vm, _, confirm) = await CreateAsync(actions, winget: new WingetStatus(false, "winget fehlt", null));
        var notice = Assert.Single(vm.Notices);
        Assert.Equal("winget installieren", notice.ActionText);

        await vm.InstallWingetCommand.ExecuteAsync(null);

        Assert.Equal("Repair-WinGetPackageManager -Latest", Assert.Single(confirm.Shown).CommandLine);
        Assert.Empty(vm.Notices);
        Assert.Contains("neuer Scan", vm.StatusText);
    });

    [Fact]
    public void LoadsHistoryOfTheSelectedProgram() => RunOnDispatcher(async () =>
    {
        var actions = new FakeActions { HistoryEntries = [new ActionHistoryEntry(new DateTime(2026, 10, 1, 8, 0, 0, DateTimeKind.Utc), "Update", "Winget", "Succeeded", null)] };
        var (vm, _, _) = await CreateAsync(actions);

        vm.SelectedItem = Tool;
        await Task.Delay(50);

        Assert.Contains("Aktualisieren über Winget · Erfolgreich", Assert.Single(vm.History).Text);
    });

    [Fact]
    public void WithoutActionServiceNoActionsAreOffered() => RunOnDispatcher(async () =>
    {
        var vm = new MainViewModel(new FakeInventory { Items = [Tool] });
        await vm.InitializeAsync();

        Assert.False(vm.ActionsAvailable);
        Assert.False(vm.UpdateCommand.CanExecute(Tool));
    });

    private sealed class FakeConfirmation : IConfirmationService
    {
        public bool Answer { get; set; } = true;
        public List<ActionOutcome> Shown { get; } = [];

        public Task<bool> ConfirmRefreshAsync(RefreshEstimate estimate) => Task.FromResult(true);

        public bool Confirm(ActionOutcome plan)
        {
            Shown.Add(plan);
            return Answer;
        }
    }

    private sealed class FakeActions : IActionService
    {
        public ActionOutcome Plan { get; set; } = Planned("Update");
        public ActionOutcome Outcome { get; set; } = new() { Action = "Update", Name = "Contoso Tool", Result = "Succeeded" };
        public SoftwareItem? Recheck { get; set; } = Tool;
        public Exception? PlanFailure { get; set; }
        public IReadOnlyList<ActionHistoryEntry> HistoryEntries { get; set; } = [];
        public List<string> Calls { get; } = [];

        public async Task<ActionOutcome> PlanAsync(SoftwareActionKind kind, PSObject? source, string method = "Auto", CancellationToken cancellationToken = default)
        {
            await Task.Yield();
            Calls.Add($"Plan:{kind}:{method}");
            return PlanFailure is null ? Plan : throw PlanFailure;
        }

        public async Task<ActionOutcome> ExecuteAsync(SoftwareActionKind kind, PSObject? source, ActionOutcome confirmedPlan, string method = "Auto", CancellationToken cancellationToken = default)
        {
            await Task.Yield();
            Calls.Add($"Execute:{kind}:{method}:{confirmedPlan.CommandLine}");
            return Outcome;
        }

        public async Task<SoftwareItem?> RecheckAsync(PSObject source, CancellationToken cancellationToken = default, bool refresh = false)
        {
            await Task.Yield();
            Calls.Add(refresh ? "Recheck:Refresh" : "Recheck");
            return Recheck;
        }

        public Task ClearCheckCacheAsync(PSObject source, CancellationToken cancellationToken = default)
        {
            Calls.Add("ClearCache");
            return Task.CompletedTask;
        }

        public Task<IReadOnlyList<ActionHistoryEntry>> GetHistoryAsync(string name, CancellationToken cancellationToken = default) =>
            Task.FromResult(HistoryEntries);
    }

    private sealed class FakeInventory : IInventoryService
    {
        public IReadOnlyList<SoftwareItem> Items { get; set; } = [];
        public WingetStatus Winget { get; set; } = new(true, null, null);

        public Task<IReadOnlyList<string>> InitializeAsync(CancellationToken cancellationToken = default) => Task.FromResult<IReadOnlyList<string>>([]);

        public Task<WingetStatus> GetWingetStatusAsync(CancellationToken cancellationToken = default) => Task.FromResult(Winget);

        public Task<ScanResult> ScanAsync(IProgress<string>? progress = null, CancellationToken cancellationToken = default, bool refresh = false) =>
            Task.FromResult(new ScanResult(Items, [], []));

        public Task<RefreshEstimate?> GetRefreshEstimateAsync(IReadOnlyList<PSObject> sources, CancellationToken cancellationToken = default) =>
            Task.FromResult<RefreshEstimate?>(null);

        public Task<InstallLocationInfo?> ResolveInstallLocationAsync(System.Management.Automation.PSObject source, CancellationToken cancellationToken = default) =>
            Task.FromResult<InstallLocationInfo?>(null);
    }
}
