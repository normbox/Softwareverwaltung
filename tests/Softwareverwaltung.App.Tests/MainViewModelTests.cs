using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;
using Softwareverwaltung.App.ViewModels;
using static Softwareverwaltung.App.Tests.TestHelpers;

namespace Softwareverwaltung.App.Tests;

public sealed class MainViewModelTests
{
    private static readonly SoftwareItem Firefox = new() { Name = "Firefox", Publisher = "Mozilla", Rating = Rating.Green, VulnerabilityCount = 0 };
    private static readonly SoftwareItem SevenZip = new() { Name = "7-Zip", Publisher = "Igor Pavlov", Rating = Rating.Yellow, UpdateAvailable = true, VulnerabilityCount = 0 };
    private static readonly SoftwareItem OldTool = new() { Name = "Old Tool", Publisher = "Contoso", Rating = Rating.Red, VulnerabilityCount = 2 };
    private static readonly SoftwareItem Unchecked = new() { Name = "Unchecked", Rating = Rating.Gray };

    [Fact]
    public void AppStartDoesNotScanUntilTheUserStartsIt() => RunOnDispatcher(async () =>
    {
        var inventory = new FakeInventory { Items = [Firefox, SevenZip] };
        var vm = new MainViewModel(inventory);
        var shell = new ShellViewModel(vm, new SettingsViewModel(new SettingsViewModelTests.FakeSettings()));

        await shell.InitializeAsync();

        // Kein Scan von selbst: externe Dienste erst nach „Scannen“
        Assert.Empty(inventory.Scans);
        Assert.True(vm.ShowNotScannedState);
        Assert.False(vm.ShowEmptyState);

        await vm.ScanCommand.ExecuteAsync(null);
        Assert.Single(inventory.Scans);
        Assert.False(vm.ShowNotScannedState);
        Assert.Equal(2, vm.Items.Count);
    });

    [Fact]
    public void ScansOnStartAndSortsByRatingThenName() => RunOnDispatcher(async () =>
    {
        var vm = new MainViewModel(new FakeInventory { Items = [Firefox, Unchecked, SevenZip, OldTool] });

        await vm.InitializeAsync();

        Assert.Equal(["Old Tool", "7-Zip", "Unchecked", "Firefox"], vm.ItemsView.Cast<SoftwareItem>().Select(i => i.Name));
        Assert.Equal("4 Programme", vm.CountText);
        Assert.StartsWith("Zuletzt gescannt", vm.StatusText);
        Assert.False(vm.IsBusy);
        Assert.Empty(vm.Notices);
    });

    [Fact]
    public void FiltersBySearchUpdatesAndRisks() => RunOnDispatcher(async () =>
    {
        var vm = new MainViewModel(new FakeInventory { Items = [Firefox, SevenZip, OldTool, Unchecked] });
        await vm.InitializeAsync();

        vm.SearchText = "mozilla";
        Assert.Equal(["Firefox"], Names(vm));
        Assert.Equal("1 von 4 Programmen", vm.CountText);

        vm.SearchText = "";
        vm.ShowUpdatesOnly = true;
        Assert.Equal(["7-Zip"], Names(vm));

        vm.ShowUpdatesOnly = false;
        vm.ShowRisksOnly = true;
        Assert.Equal(["Old Tool"], Names(vm));
    });

    [Fact]
    public void ShowsWingetNoticeWithStoreLinkAndKeepsItAcrossScans() => RunOnDispatcher(async () =>
    {
        var url = new Uri("https://apps.microsoft.com/detail/9NBLGGH4NNS1");
        var vm = new MainViewModel(new FakeInventory { Winget = new WingetStatus(false, "winget fehlt", url) });

        await vm.InitializeAsync();
        await vm.ScanCommand.ExecuteAsync(null);

        var notice = Assert.Single(vm.Notices);
        Assert.Equal(NoticeSeverity.Warning, notice.Severity);
        Assert.Equal("winget fehlt", notice.Message);
        Assert.Equal(url, notice.Link);
    });

    [Fact]
    public void ReplacesScanWarningsOnEachScan() => RunOnDispatcher(async () =>
    {
        var inventory = new FakeInventory { Warnings = ["Keine Quelle aktiviert."] };
        var vm = new MainViewModel(inventory);

        await vm.InitializeAsync();
        await vm.ScanCommand.ExecuteAsync(null);

        Assert.Equal("Keine Quelle aktiviert.", Assert.Single(vm.Notices).Message);
        Assert.True(vm.ShowEmptyState);

        inventory.Warnings = [];
        inventory.Items = [Firefox];
        await vm.ScanCommand.ExecuteAsync(null);
        Assert.Empty(vm.Notices);
        Assert.False(vm.ShowEmptyState);
    });

    [Fact]
    public void ShowsModuleErrorsAndStartupFailures() => RunOnDispatcher(async () =>
    {
        var vm = new MainViewModel(new FakeInventory { Errors = ["Registry nicht lesbar"] });
        await vm.InitializeAsync();
        Assert.Equal(NoticeSeverity.Error, Assert.Single(vm.Notices).Severity);

        var broken = new MainViewModel(new FakeInventory { StartupFailure = new InvalidOperationException("Kern-Modul fehlt") });
        await broken.InitializeAsync();
        Assert.Equal("Kern-Modul fehlt", Assert.Single(broken.Notices).Message);
        Assert.False(broken.ScanCommand.CanExecute(null));
    });

    [Fact]
    public void DismissesNotices() => RunOnDispatcher(async () =>
    {
        var vm = new MainViewModel(new FakeInventory { Warnings = ["Hinweis"] });
        await vm.InitializeAsync();

        vm.DismissNoticeCommand.Execute(vm.Notices[0]);

        Assert.Empty(vm.Notices);
    });

    [Fact]
    public void CancelledScanKeepsPreviousList() => RunOnDispatcher(async () =>
    {
        var inventory = new FakeInventory { Items = [Firefox] };
        var vm = new MainViewModel(inventory);
        await vm.InitializeAsync();

        inventory.Cancel = true;
        await vm.ScanCommand.ExecuteAsync(null);

        Assert.Equal(["Firefox"], Names(vm));
        Assert.Equal("Scan abgebrochen.", vm.StatusText);
    });

    [Fact]
    public void ResolvesInstallFolderOnExpandOnceAndOffersOpenAndCopy() => RunOnDispatcher(async () =>
    {
        var tool = new SoftwareItem { Name = "Contoso Tool", InstalledVersion = "1.0", Source = new System.Management.Automation.PSObject() };
        var inventory = new FakeInventory
        {
            Items = [tool],
            Location = new InstallLocationInfo(@"C:\Program Files\Contoso", "vermutlich, abgeleitet aus dem Programmsymbol", null, CanOpen: true),
        };
        var shell = new FakeShell();
        var vm = new MainViewModel(inventory, shell: shell);
        await vm.InitializeAsync();

        vm.SelectedItem = tool;
        vm.OpenDetailsCommand.Execute(null);
        await Task.Yield();
        Assert.Equal(@"C:\Program Files\Contoso", vm.SelectedLocation?.Path);
        Assert.True(vm.OpenFolderCommand.CanExecute(null));
        vm.OpenFolderCommand.Execute(null);
        vm.CopyPathCommand.Execute(null);
        Assert.Equal([@"C:\Program Files\Contoso"], shell.Opened);
        Assert.Equal([@"C:\Program Files\Contoso"], shell.Copied);

        // Schließen und wieder öffnen: für die Sitzung gemerkt, nicht neu ermittelt.
        vm.CloseDetailsCommand.Execute(null);
        Assert.False(vm.IsDetailsOpen);
        Assert.Same(tool, vm.SelectedItem);   // Auswahl bleibt, der Fokus geht in der Liste weiter
        vm.OpenDetailsCommand.Execute(null);
        await Task.Yield();
        Assert.NotNull(vm.SelectedLocation);
        Assert.Equal(1, inventory.ResolveCalls);
    });

    [Fact]
    public void DetailsPanelFollowsTheSelectionOnlyWhileOpen() => RunOnDispatcher(async () =>
    {
        var a = new SoftwareItem { Name = "Alpha", Source = new System.Management.Automation.PSObject() };
        var b = new SoftwareItem { Name = "Beta", Source = new System.Management.Automation.PSObject() };
        var inventory = new FakeInventory { Items = [a, b], Location = new InstallLocationInfo(@"C:\Tools", null, null, CanOpen: true) };
        var vm = new MainViewModel(inventory);
        await vm.InitializeAsync();

        // Ohne Auswahl öffnet nichts; ↑/↓ bei geschlossenem Feld fragt nichts ab.
        vm.OpenDetailsCommand.Execute(null);
        Assert.False(vm.IsDetailsOpen);
        vm.SelectedItem = a;
        await Task.Yield();
        Assert.Equal(0, inventory.ResolveCalls);

        // Offen: eine andere Zeile wechselt den Inhalt.
        vm.OpenDetailsCommand.Execute(null);
        await Task.Yield();
        vm.SelectedItem = b;
        await Task.Yield();
        Assert.True(vm.IsDetailsOpen);
        Assert.Equal(2, inventory.ResolveCalls);

        // Verschwindet die Auswahl (z. B. nach einem Scan), schließt das Feld.
        vm.SelectedItem = null;
        Assert.False(vm.IsDetailsOpen);
    });

    [Fact]
    public void RemembersTheDetailsWidth() => RunOnDispatcher(async () =>
    {
        var store = new MemoryAppUiStore();
        store.Save(new AppUiSettings { DetailsWidthFraction = 0.55 });
        var vm = new MainViewModel(new FakeInventory(), ui: store);
        await vm.InitializeAsync();

        Assert.Equal(0.55, vm.DetailsWidthFraction);
        vm.DetailsWidthFraction = 0.3;
        Assert.Equal(0.3, store.Current.DetailsWidthFraction);
        Assert.Equal(AppUiSettings.DefaultDetailsWidthFraction, new MainViewModel(new FakeInventory()).DetailsWidthFraction);
    });

    [Fact]
    public void HidesOpenForStoreAppsAndCopyForUnknownFolders() => RunOnDispatcher(async () =>
    {
        var app = new SoftwareItem { Name = "Store App", Source = new System.Management.Automation.PSObject() };
        var inventory = new FakeInventory { Items = [app], Location = new InstallLocationInfo(@"C:\Program Files\WindowsApps\X", "laut App-Paket", null, CanOpen: false) };
        var vm = new MainViewModel(inventory, shell: new FakeShell());
        await vm.InitializeAsync();

        vm.SelectedItem = app;
        vm.OpenDetailsCommand.Execute(null);
        await Task.Yield();
        Assert.False(vm.OpenFolderCommand.CanExecute(null));
        Assert.True(vm.CopyPathCommand.CanExecute(null));

        var unknown = new SoftwareItem { Name = "Unknown", Source = new System.Management.Automation.PSObject() };
        inventory.Location = new InstallLocationInfo(null, null, "Weder Installer-Eintrag noch Programmsymbol …", CanOpen: false);
        vm.SelectedItem = unknown;
        await Task.Yield();
        Assert.False(vm.SelectedLocation!.IsKnown);
        Assert.False(vm.CopyPathCommand.CanExecute(null));
    });

    [Fact]
    public void ScanWithoutCacheSwitchAsksOnlyWhenTheModuleSaysSo() => RunOnDispatcher(async () =>
    {
        var tool = new SoftwareItem { Name = "Contoso Tool", Source = new System.Management.Automation.PSObject() };
        var inventory = new FakeInventory { Items = [tool], Estimate = new RefreshEstimate(12, 72, NeedsConfirmation: true) };
        var confirmation = new FakeRefreshConfirmation { Answer = false };
        var vm = new MainViewModel(inventory, confirmation: confirmation);
        await vm.InitializeAsync();

        // Ohne NVD-Schlüssel: Rückfrage mit Schätzung beim Einschalten; abgelehnt = Schalter wieder aus.
        vm.ScanWithoutCache = true;
        await Task.Delay(50);
        Assert.Equal([72], confirmation.Asked);
        Assert.False(vm.ScanWithoutCache);

        confirmation.Answer = true;
        vm.ScanWithoutCache = true;
        await Task.Delay(50);
        Assert.True(vm.ScanWithoutCache);
        await vm.ScanCommand.ExecuteAsync(null);

        // Mit Schlüssel: ohne Rückfrage; ausgeschaltet scannt „Scannen“ wieder mit Cache.
        vm.ScanWithoutCache = false;
        inventory.Estimate = new RefreshEstimate(12, 8, NeedsConfirmation: false);
        vm.ScanWithoutCache = true;
        await Task.Delay(50);
        Assert.Equal(2, confirmation.Asked.Count);
        await vm.ScanCommand.ExecuteAsync(null);
        vm.ScanWithoutCache = false;
        await vm.ScanCommand.ExecuteAsync(null);
        Assert.Equal([false, true, true, false], inventory.Scans);
    });

    [Fact]
    public void ShowsCheckAgeAndMarksStaleData()
    {
        var now = new DateTime(2026, 10, 28, 12, 0, 0, DateTimeKind.Utc);
        Assert.Equal("", SoftwareItem.FormatAge(null, now));
        Assert.Equal("gerade eben", SoftwareItem.FormatAge(now.AddSeconds(-20), now));
        Assert.Equal("vor 5 min", SoftwareItem.FormatAge(now.AddMinutes(-5), now));
        Assert.Equal("vor 2 h", SoftwareItem.FormatAge(now.AddHours(-2), now));
        Assert.Equal("vor 3 Tagen", SoftwareItem.FormatAge(now.AddDays(-3), now));

        var item = SoftwareItem.FromRating(Ps(("Name", "Tool"), ("Rating", "Green"),
            ("CheckedAt", now.AddHours(-30)), ("UpdateCheckedAt", now.AddHours(-1)), ("VulnerabilityCheckedAt", now.AddHours(-30)), ("CheckStale", true)));
        Assert.True(item.CheckStale);
        Assert.Equal(now.AddHours(-30), item.CheckedAt);
        Assert.Contains("Neueste Version geprüft", item.CheckedTooltip);
        Assert.Contains("Sicherheitslücken geprüft", item.CheckedTooltip);
        Assert.Contains("Älter als die eingestellte Haltbarkeit", item.CheckedTooltip);
        Assert.Null(SoftwareItem.FromRating(Ps(("Name", "Tool"))).CheckedTooltip);
    }

    private sealed class FakeRefreshConfirmation : IConfirmationService
    {
        public bool Answer { get; set; }
        public List<int> Asked { get; } = [];

        public bool Confirm(ActionOutcome plan) => true;

        public bool ConfirmQueue(QueueConfirmation confirmation) => true;

        public bool ConfirmStoreAgreement(StoreAgreement agreement) => false;

        public CpeMappingChoice? ChooseCpe(ViewModels.CpeMappingViewModel viewModel) => null;

        public Task<bool> ConfirmCpeReportAsync(CpeReport report) => Task.FromResult(false);

        public Task<bool> ConfirmRefreshAsync(RefreshEstimate estimate)
        {
            Asked.Add(estimate.Seconds);
            return Task.FromResult(Answer);
        }
    }

    private static List<string> Names(MainViewModel vm) => vm.ItemsView.Cast<SoftwareItem>().Select(i => i.Name).ToList();

    private sealed class FakeInventory : IInventoryService
    {
        public IReadOnlyList<SoftwareItem> Items { get; set; } = [];
        public IReadOnlyList<string> Warnings { get; set; } = [];
        public IReadOnlyList<string> Errors { get; set; } = [];
        public WingetStatus Winget { get; set; } = new(true, null, null);
        public Exception? StartupFailure { get; set; }
        public bool Cancel { get; set; }

        public Task<IReadOnlyList<string>> InitializeAsync(CancellationToken cancellationToken = default) =>
            StartupFailure is null ? Task.FromResult<IReadOnlyList<string>>([]) : Task.FromException<IReadOnlyList<string>>(StartupFailure);

        public Task<WingetStatus> GetWingetStatusAsync(CancellationToken cancellationToken = default) => Task.FromResult(Winget);

        public List<bool> Scans { get; } = [];
        public RefreshEstimate? Estimate { get; set; }

        public Task<RefreshEstimate?> GetRefreshEstimateAsync(IReadOnlyList<System.Management.Automation.PSObject> sources, CancellationToken cancellationToken = default) =>
            Task.FromResult(Estimate);

        public async Task<ScanResult> ScanAsync(IProgress<string>? progress = null, CancellationToken cancellationToken = default, bool refresh = false)
        {
            Scans.Add(refresh);
            await Task.Yield();
            if (Cancel)
            {
                throw new OperationCanceledException();
            }
            return new ScanResult(Items, Warnings, Errors);
        }

        public InstallLocationInfo? Location { get; set; }
        public int ResolveCalls { get; private set; }

        public Task<InstallLocationInfo?> ResolveInstallLocationAsync(System.Management.Automation.PSObject source, CancellationToken cancellationToken = default)
        {
            ResolveCalls++;
            return Task.FromResult(Location);
        }
    }

    private sealed class FakeShell : IShellService
    {
        public List<string> Opened { get; } = [];
        public List<string> Copied { get; } = [];

        public void OpenFolder(string path) => Opened.Add(path);

        public void CopyText(string text) => Copied.Add(text);

        public void OpenUrl(Uri url) => Opened.Add(url.AbsoluteUri);
    }
}
