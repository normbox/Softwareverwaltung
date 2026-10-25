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

        public async Task<ScanResult> ScanAsync(IProgress<string>? progress = null, CancellationToken cancellationToken = default)
        {
            await Task.Yield();
            if (Cancel)
            {
                throw new OperationCanceledException();
            }
            return new ScanResult(Items, Warnings, Errors);
        }
    }
}
