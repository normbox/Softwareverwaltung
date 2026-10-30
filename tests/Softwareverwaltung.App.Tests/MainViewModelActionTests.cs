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

    private static async Task<(MainViewModel Vm, FakeActions Actions, FakeConfirmation Confirm)> CreateAsync(FakeActions? actions = null, bool confirm = true, WingetStatus? winget = null,
        ICpeService? cpe = null, IShellService? shell = null, SoftwareItem? item = null)
    {
        actions ??= new FakeActions();
        var confirmation = new FakeConfirmation { Answer = confirm };
        var vm = new MainViewModel(new FakeInventory { Items = [item ?? Tool], Winget = winget ?? new WingetStatus(true, null, null) }, actions, confirmation, shell: shell, cpe: cpe);
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
        vm.OpenDetailsCommand.Execute(null);
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

    private static QueueEntry Entry(int index, string name, bool executable, bool elevated = false, bool unconfirmed = false) =>
        new(index, name, "1.0", "2.0", unconfirmed, executable, elevated, executable ? $"winget upgrade --id {name}" : null,
            executable ? null : "Update von Hand nötig", Ps(("Index", index), ("Name", name)));

    [Fact]
    public void QueueSelectsAllWithUpdateConfirmsRunsAndRechecksOnlyAffectedPrograms() => RunOnDispatcher(async () =>
    {
        var a = new SoftwareItem { Name = "Alpha", UpdateAvailable = true, Source = Ps(("Name", "Alpha")) };
        var b = new SoftwareItem { Name = "Beta", UpdateAvailable = true, Source = Ps(("Name", "Beta")) };
        var c = new SoftwareItem { Name = "Gamma", UpdateAvailable = false, Source = Ps(("Name", "Gamma")) };
        var actions = new FakeActions
        {
            QueuePlan = [Entry(0, "Alpha", executable: true, elevated: true, unconfirmed: true), Entry(1, "Beta", executable: false)],
            QueueResults = [new ActionOutcome { Action = "Update", Name = "Alpha", Result = "Succeeded" }],
        };
        var confirmation = new FakeConfirmation();
        var vm = new MainViewModel(new FakeInventory { Items = [a, b, c] }, actions, confirmation);
        await vm.InitializeAsync();

        vm.SelectAllWithUpdateCommand.Execute(null);
        Assert.Equal(2, vm.QueueSelectedCount);
        Assert.False(c.Queue.IsChecked);

        await vm.UpdateSelectedCommand.ExecuteAsync(null);

        // Gemeinsame Bestätigung: Gruppen und Kennzeichnung „unbestätigt“
        var shown = Assert.Single(confirmation.Queues);
        Assert.Equal(["Alpha"], shown.Elevated.Select(e => e.Name));
        Assert.Empty(shown.Normal);
        Assert.Equal(["Beta"], shown.NotExecutable.Select(e => e.Name));
        Assert.True(shown.Elevated[0].Unconfirmed);
        // Nur ausführbare Einträge laufen; danach nur das betroffene Programm verwerfen und neu prüfen
        Assert.Equal(["Alpha"], actions.QueueRun);
        Assert.Equal(["QueuePlan", "QueueRun", "ClearCache", "Recheck"], actions.Calls);
        Assert.Equal("Succeeded", Assert.Single(vm.QueueEntries).Status);
        Assert.Equal(0, vm.QueueSelectedCount);
        Assert.False(vm.QueueRunning);
    });

    [Fact]
    public void QueueRunsNothingWhenTheConfirmationIsDeclined() => RunOnDispatcher(async () =>
    {
        var a = new SoftwareItem { Name = "Alpha", UpdateAvailable = true, Source = Ps(("Name", "Alpha")) };
        var actions = new FakeActions { QueuePlan = [Entry(0, "Alpha", executable: true)] };
        var vm = new MainViewModel(new FakeInventory { Items = [a] }, actions, new FakeConfirmation { Answer = false });
        await vm.InitializeAsync();
        a.Queue.IsChecked = true;

        await vm.UpdateSelectedCommand.ExecuteAsync(null);

        Assert.Equal(["QueuePlan"], actions.Calls);
        Assert.Empty(vm.QueueEntries);
    });

    [Fact]
    public void QueuePauseResumeAndCancelSetTheSharedControl() => RunOnDispatcher(async () =>
    {
        var a = new SoftwareItem { Name = "Alpha", UpdateAvailable = true, Source = Ps(("Name", "Alpha")) };
        var actions = new FakeActions { QueuePlan = [Entry(0, "Alpha", executable: true)], HoldQueue = new TaskCompletionSource() };
        var vm = new MainViewModel(new FakeInventory { Items = [a] }, actions, new FakeConfirmation());
        await vm.InitializeAsync();
        a.Queue.IsChecked = true;

        var running = vm.UpdateSelectedCommand.ExecuteAsync(null);
        while (actions.Control is null)
        {
            await Task.Delay(10);
        }
        Assert.True(vm.QueueRunning);
        vm.PauseQueueCommand.Execute(null);
        Assert.Equal("Paused", actions.Control["State"]);
        Assert.True(vm.ResumeQueueCommand.CanExecute(null));
        vm.ResumeQueueCommand.Execute(null);
        Assert.Equal("Running", actions.Control["State"]);
        vm.CancelQueueCommand.Execute(null);
        Assert.Equal("Cancelled", actions.Control["State"]);

        var finished = false;
        vm.QueueFinished += (_, _) => finished = true;
        actions.HoldQueue.SetResult();
        await running;
        Assert.True(finished);
        Assert.False(vm.QueueRunning);
    });

    [Fact]
    public void StorePackageAsksForTheStoreAgreementOnceAndRunsOnlyAfterConsent() => RunOnDispatcher(async () =>
    {
        var actions = new FakeActions { StorePackage = true, Plan = Planned("Update") };
        var (vm, _, confirm) = await CreateAsync(actions);

        // Abgelehnt: nichts ausgeführt, Ergebnis nennt den Grund
        confirm.StoreAnswer = false;
        await vm.UpdateCommand.ExecuteAsync(Tool);
        Assert.Equal(["Plan:Update:Auto", "StoreAgreement"], actions.Calls);
        Assert.True(vm.LastOutcome!.IsStoreAgreementRequired);
        Assert.Equal("Store-Vereinbarung nicht bestätigt", vm.LastOutcome.ResultText);

        // Zugestimmt: Zustimmung speichern, neu planen, normal bestätigen und ausführen
        actions.Calls.Clear();
        confirm.StoreAnswer = true;
        await vm.UpdateCommand.ExecuteAsync(Tool);
        Assert.Equal(["Plan:Update:Auto", "StoreAgreement", "AcceptStoreAgreement", "Plan:Update:Auto"], actions.Calls.Take(4));
        Assert.Contains(actions.Calls, c => c.StartsWith("Execute:Update", StringComparison.Ordinal));
    });

    [Fact]
    public void MapCpeSavesOnlyTheConfirmedChoiceAndRechecksTheRow() => RunOnDispatcher(async () =>
    {
        var noCpe = Tool with { NeedsCpe = true };
        var mapped = noCpe with { NeedsCpe = false, CpeSource = "User", CpeBase = ["cpe:2.3:a:contoso:tool"] };
        var cpe = new FakeCpe();
        var actions = new FakeActions { Recheck = mapped };
        var (vm, _, confirm) = await CreateAsync(actions, cpe: cpe, item: noCpe);
        var row = vm.Items[0];

        // Abgebrochen: nichts gespeichert, nichts neu geprüft
        confirm.CpeChoice = null;
        await vm.MapCpeCommand.ExecuteAsync(row);
        Assert.NotNull(confirm.CpeDialog);
        Assert.DoesNotContain(cpe.Calls, c => c.StartsWith("Set", StringComparison.Ordinal));
        Assert.DoesNotContain(actions.Calls, c => c.StartsWith("Recheck", StringComparison.Ordinal));

        // Zugeordnet: speichern, nur diese Zeile neu prüfen
        confirm.CpeChoice = CpeMappingChoice.Assign("cpe:2.3:a:contoso:tool");
        await vm.MapCpeCommand.ExecuteAsync(row);
        Assert.Contains("Set:cpe:2.3:a:contoso:tool", cpe.Calls);
        Assert.Contains(actions.Calls, c => c.StartsWith("Recheck", StringComparison.Ordinal));
        Assert.True(vm.Items[0].HasUserCpe);

        // Eigene Zuordnung entfernen
        confirm.CpeChoice = CpeMappingChoice.RemoveMapping;
        await vm.MapCpeCommand.ExecuteAsync(vm.Items[0]);
        Assert.Contains("Remove", cpe.Calls);
    });

    [Fact]
    public void MapCpeIsNotOfferedForCatalogEntries() => RunOnDispatcher(async () =>
    {
        var catalog = Tool with { CpeSource = "Catalog", CpeBase = ["cpe:2.3:a:contoso:tool"] };
        var (vm, _, _) = await CreateAsync(cpe: new FakeCpe(), item: catalog);
        Assert.False(vm.MapCpeCommand.CanExecute(vm.Items[0]));
        Assert.False(vm.ReportCpeCommand.CanExecute(vm.Items[0]));
    });

    [Fact]
    public void ReportCpeOpensTheBrowserOnlyAfterConfirmation() => RunOnDispatcher(async () =>
    {
        var own = Tool with { CpeSource = "User", CpeBase = ["cpe:2.3:a:contoso:tool"] };
        var cpe = new FakeCpe();
        var shell = new RecordingShell();
        var (vm, _, confirm) = await CreateAsync(cpe: cpe, shell: shell, item: own);

        confirm.ReportAnswer = false;
        await vm.ReportCpeCommand.ExecuteAsync(vm.Items[0]);
        Assert.Equal(cpe.Report, confirm.ShownReport);
        Assert.Empty(shell.OpenedUrls);

        confirm.ReportAnswer = true;
        await vm.ReportCpeCommand.ExecuteAsync(vm.Items[0]);
        Assert.Equal([cpe.Report.Url], shell.OpenedUrls);
    });

    private sealed class FakeConfirmation : IConfirmationService
    {
        public bool Answer { get; set; } = true;
        public bool StoreAnswer { get; set; } = true;

        public bool ConfirmStoreAgreement(StoreAgreement agreement) => StoreAnswer;

        public CpeMappingChoice? CpeChoice { get; set; }
        public ViewModels.CpeMappingViewModel? CpeDialog { get; private set; }

        public CpeMappingChoice? ChooseCpe(ViewModels.CpeMappingViewModel viewModel)
        {
            CpeDialog = viewModel;
            return CpeChoice;
        }

        public bool ReportAnswer { get; set; }
        public CpeReport? ShownReport { get; private set; }

        public Task<bool> ConfirmCpeReportAsync(CpeReport report)
        {
            ShownReport = report;
            return Task.FromResult(ReportAnswer);
        }
        public List<ActionOutcome> Shown { get; } = [];
        public List<QueueConfirmation> Queues { get; } = [];

        public bool ConfirmQueue(QueueConfirmation confirmation)
        {
            Queues.Add(confirmation);
            return Answer;
        }

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
            // Store-Paket: ohne Zustimmung nicht ausführbar, danach wie geplant
            if (StorePackage && !StoreAgreementAccepted)
            {
                return new ActionOutcome { Action = kind.ToString(), Name = "Store App", Result = "StoreAgreementRequired", Message = "Store-Vereinbarung noch nicht bestätigt." };
            }
            return PlanFailure is null ? Plan : throw PlanFailure;
        }

        public bool StorePackage { get; set; }

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

        public bool StoreAgreementAccepted { get; private set; }

        public Task<StoreAgreement> GetStoreAgreementAsync(CancellationToken cancellationToken = default)
        {
            Calls.Add("StoreAgreement");
            return Task.FromResult(new StoreAgreement("Vereinbarung", null));
        }

        public Task AcceptStoreAgreementAsync(CancellationToken cancellationToken = default)
        {
            Calls.Add("AcceptStoreAgreement");
            StoreAgreementAccepted = true;
            return Task.CompletedTask;
        }

        public IReadOnlyList<QueueEntry> QueuePlan { get; set; } = [];
        public IReadOnlyList<ActionOutcome> QueueResults { get; set; } = [];
        public List<string> QueueRun { get; } = [];
        public System.Collections.Hashtable? Control { get; private set; }
        public TaskCompletionSource? HoldQueue { get; set; }

        public Task<IReadOnlyList<QueueEntry>> PlanUpdateQueueAsync(IReadOnlyList<PSObject> sources, IProgress<string>? progress = null, CancellationToken cancellationToken = default)
        {
            Calls.Add("QueuePlan");
            return Task.FromResult(QueuePlan);
        }

        public async Task<IReadOnlyList<ActionOutcome>> RunUpdateQueueAsync(IReadOnlyList<QueueEntry> entries, System.Collections.Hashtable control, IProgress<string>? progress = null)
        {
            Calls.Add("QueueRun");
            QueueRun.AddRange(entries.Select(e => e.Name));
            Control = control;
            if (HoldQueue is not null)
            {
                await HoldQueue.Task;
            }
            // Wie das Modul: Status je Index in der gemeinsamen Steuerung
            control["Status"] = System.Collections.Hashtable.Synchronized(new System.Collections.Hashtable(
                QueueResults.Select((r, i) => (entries[i].Index, r.Result)).ToDictionary(x => (object)x.Index, x => (object)x.Result)));
            return QueueResults;
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
