using System.Management.Automation;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;
using Softwareverwaltung.App.ViewModels;
using static Softwareverwaltung.App.Tests.TestHelpers;

namespace Softwareverwaltung.App.Tests;

public sealed class CpeMappingTests
{
    private static readonly SoftwareItem Gimp = new()
    {
        Name = "GIMP 3.2.4", Publisher = "The GIMP Team", InstalledVersion = "3.2.4", NeedsCpe = true,
        Source = Ps(("Name", "GIMP 3.2.4")),
    };

    [Fact]
    public void ValidatesCpeLikeTheModule()
    {
        Assert.True(CpeName.IsValid("cpe:2.3:a:gimp:gimp"));
        Assert.True(CpeName.IsValid(@"cpe:2.3:a:notepad-plus-plus:notepad\+\+"));
        Assert.False(CpeName.IsValid("cpe:2.3:a:gimp:gimp:3.2"));   // mit Version
        Assert.False(CpeName.IsValid("gimp"));
    }

    [Fact]
    public void ItemOffersMappingOnlyWithoutCpeOrForOwnMapping()
    {
        Assert.True(Gimp.CanMapCpe);
        Assert.False(Gimp.HasUserCpe);
        var catalog = Gimp with { NeedsCpe = false, CpeSource = "Catalog", CpeBase = ["cpe:2.3:a:gimp:gimp"] };
        Assert.False(catalog.CanMapCpe);
        var own = Gimp with { NeedsCpe = false, CpeSource = "User", CpeBase = ["cpe:2.3:a:gimp:gimp"] };
        Assert.True(own.CanMapCpe);
        Assert.True(own.HasUserCpe);
        Assert.Equal("cpe:2.3:a:gimp:gimp (von Ihnen bestätigt)", own.CpeText);
    }

    [Fact]
    public async Task SuggestionsOnlyFillTheInputAndAssignNeedsAValidCpe()
    {
        var cpe = new FakeCpe { Candidates = [new CpeCandidate("cpe:2.3:a:gimp:gimp", "gimp", "gimp", 5, 40, null)] };
        var vm = new CpeMappingViewModel(Gimp, cpe);
        await vm.SearchAsync();

        Assert.Single(vm.Candidates);
        Assert.Null(vm.Hint);
        Assert.False(vm.AssignCommand.CanExecute(null));

        vm.SelectedCandidate = vm.Candidates[0];
        Assert.Equal("cpe:2.3:a:gimp:gimp", vm.CpeText);
        Assert.Null(vm.Choice);   // nur übernommen, nicht zugeordnet

        vm.CpeText = "cpe:2.3:a:gimp:gimp:3";
        Assert.True(vm.ShowCpeInvalid);
        Assert.False(vm.AssignCommand.CanExecute(null));

        vm.CpeText = " cpe:2.3:a:gimp:gimp ";
        var closed = false;
        vm.CloseRequested += (_, _) => closed = true;
        vm.AssignCommand.Execute(null);
        Assert.True(closed);
        Assert.Equal("cpe:2.3:a:gimp:gimp", vm.Choice!.Cpe);
    }

    [Fact]
    public async Task ShowsHintWhenNoSuggestionsOrSearchFails()
    {
        var vm = new CpeMappingViewModel(Gimp, new FakeCpe { Hint = "Dienst NVD ist nicht aktiviert." });
        await vm.SearchAsync();
        Assert.Equal("Dienst NVD ist nicht aktiviert.", vm.Hint);
        Assert.True(vm.ShowHint);

        var failing = new CpeMappingViewModel(Gimp, new FakeCpe { Failure = new InvalidOperationException("offline") });
        await failing.SearchAsync();
        Assert.Contains("offline", failing.Hint, StringComparison.Ordinal);
        Assert.False(failing.IsSearching);
    }
}

internal sealed class FakeCpe : ICpeService
{
    public IReadOnlyList<CpeCandidate> Candidates { get; set; } = [];
    public string? Hint { get; set; }
    public Exception? Failure { get; set; }
    public List<string> Calls { get; } = [];
    public CpeReport Report { get; set; } = new("CPE-Zuordnung: Contoso Tool", new Uri("https://github.com/normbox/Softwareverwaltung/issues/new?template=cpe-zuordnung.yml"), "program: Contoso Tool");

    public async Task<CpeSearchResult> FindCandidatesAsync(PSObject source, CancellationToken cancellationToken = default)
    {
        await Task.Yield();
        Calls.Add("Find");
        return Failure is null ? new CpeSearchResult(Candidates, Candidates.Count == 0 ? Hint : null) : throw Failure;
    }

    public Task SetMappingAsync(PSObject source, string cpe, CancellationToken cancellationToken = default)
    {
        Calls.Add($"Set:{cpe}");
        return Task.CompletedTask;
    }

    public Task RemoveMappingAsync(PSObject source, CancellationToken cancellationToken = default)
    {
        Calls.Add("Remove");
        return Task.CompletedTask;
    }

    public Task<CpeReport> GetReportAsync(PSObject source, CancellationToken cancellationToken = default)
    {
        Calls.Add("Report");
        return Task.FromResult(Report);
    }
}

internal sealed class RecordingShell : IShellService
{
    public List<Uri> OpenedUrls { get; } = [];

    public void OpenFolder(string path)
    {
    }

    public void CopyText(string text)
    {
    }

    public void OpenUrl(Uri url) => OpenedUrls.Add(url);
}
