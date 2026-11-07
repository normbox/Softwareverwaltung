using System.Management.Automation;
using System.Security;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;
using Softwareverwaltung.App.ViewModels;

namespace Softwareverwaltung.App.Tests;

/// <summary>
/// Echtes Modul in der eingebetteten Engine. Einstellungsdatei und Einträge in der
/// Anmeldeinformationsverwaltung werden auf Testwerte umgelenkt, echte Daten bleiben unberührt.
/// </summary>
public sealed class SettingsServiceTests : IAsyncLifetime
{
    private readonly PowerShellHost _host = new();
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "SoftwareverwaltungTests", Guid.NewGuid().ToString("N"));
    private readonly string _prefix = "SoftwareInventory-AppTest-" + Guid.NewGuid().ToString("N");
    private SettingsService _service = null!;

    public async Task InitializeAsync()
    {
        Directory.CreateDirectory(_directory);
        await RedirectAsync(_host);
        _service = new SettingsService(_host);
    }

    /// <summary>Nur in dieser Runspace: Einstellungsdatei und Präfix der Anmeldeinformationen auf Testwerte umlenken.</summary>
    private async Task RedirectAsync(PowerShellHost host)
    {
        await host.InitializeAsync();
        var result = await host.InvokeAsync(new PSCommand().AddScript("""
            param($File, $Prefix)
            & (Get-Module SoftwareInventory) {
                param($File, $Prefix)
                $script:TestSettingsFile = $File
                function script:Get-SettingsPath { $script:TestSettingsFile }
                $script:CredentialPrefix = $Prefix
            } $File $Prefix
            """).AddParameter("File", Path.Combine(_directory, "settings.json")).AddParameter("Prefix", _prefix));
        Assert.Empty(result.Errors);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task ClosedShareLevelNoticeComesBackAfterRestartOnlyWithoutTheCheckbox(bool dontShowAgain)
    {
        // Übernommene ältere Einstellungen ohne Freigabestufe: lokal Stufe 2 mit einmaligem Hinweis
        File.WriteAllText(Path.Combine(_directory, "settings.json"),
            """{"Usage":"Private","Advisor":{"Enabled":true,"Preset":"Ollama","Endpoint":"http://localhost:11434/v1","Model":"m"}}""");
        var vm = new SettingsViewModel(_service);
        await vm.LoadAsync();
        Assert.True(vm.ShowShareLevelNotice);
        Assert.True(vm.ShowShareLevelNoticeInMain);
        Assert.True(vm.DismissShareLevelNoticeCommand.CanExecute(null));

        vm.DontShowShareLevelNoticeAgain = dontShowAgain;
        await vm.DismissShareLevelNoticeCommand.ExecuteAsync(null);
        Assert.False(vm.ShowShareLevelNotice);
        Assert.False(vm.ShowShareLevelNoticeInMain);

        // Neustart: neue Engine, neues ViewModel, dieselbe Einstellungsdatei
        using var restarted = new PowerShellHost();
        await RedirectAsync(restarted);
        var again = new SettingsViewModel(new SettingsService(restarted));
        await again.LoadAsync();
        Assert.Equal(!dontShowAgain, again.ShowShareLevelNotice);
        Assert.Equal(!dontShowAgain, again.ShowShareLevelNoticeInMain);
        Assert.Equal(2, again.AdvisorShareLevelLocal);
    }

    public async Task DisposeAsync()
    {
        await _service.RemoveCredentialAsync("NVD");
        await _service.RemoveCredentialAsync("GitHub");
        _host.Dispose();
        Directory.Delete(_directory, recursive: true);
    }

    [Fact]
    public async Task AdvisorValuesRoundTripWithoutDefaultModel()
    {
        var initial = await _service.LoadAsync();
        Assert.False(initial.AdvisorEnabled);
        Assert.Null(initial.AdvisorModel);
        Assert.Equal(3, initial.AdvisorShareLevelLocal);
        Assert.False(initial.AdvisorShareLevelNoticePending);

        var saved = await _service.SaveAsync(initial with { AdvisorPreset = "LMStudio", AdvisorEndpoint = "http://127.0.0.1:1234/v1", AdvisorModel = "qwen3:8b", AdvisorEnabled = true, AdvisorShareLevelLocal = 1 }, initial);

        var loaded = await _service.LoadAsync();
        foreach (var settings in new[] { saved, loaded })
        {
            Assert.True(settings.AdvisorEnabled);
            Assert.Equal("LMStudio", settings.AdvisorPreset);
            Assert.Equal("http://127.0.0.1:1234/v1", settings.AdvisorEndpoint);
            Assert.Equal("qwen3:8b", settings.AdvisorModel);
            Assert.Equal(1, settings.AdvisorShareLevelLocal);
        }
        Assert.Contains(await _service.GetAdvisorPresetsAsync(), p => p.Name == "Unsloth" && p.RequiresApiKey && p.Endpoint is not null);
    }

    [Fact]
    public async Task AdvisorRulesOfTheModuleApplyWhenSaving()
    {
        var initial = await _service.LoadAsync();

        var incomplete = await Assert.ThrowsAsync<InvalidOperationException>(() => _service.SaveAsync(initial with { AdvisorPreset = "Ollama", AdvisorEndpoint = "http://localhost:11434/v1", AdvisorEnabled = true }, initial));
        Assert.Contains("Modell", incomplete.Message);

        var publicAddress = await Assert.ThrowsAsync<InvalidOperationException>(() => _service.SaveAsync(initial with { AdvisorPreset = "Custom", AdvisorEndpoint = "https://8.8.8.8/v1" }, initial));
        Assert.Contains("8.8.8.8", publicAddress.Message);
    }

    [Fact]
    public async Task UnchangedAdvisorAddressIsNotCheckedAgain()
    {
        // Gespeicherte Adresse, die sich (z. B. ohne Heimnetz) gerade nicht auflösen lässt
        File.WriteAllText(Path.Combine(_directory, "settings.json"),
            """{"Advisor":{"Enabled":false,"Preset":"Custom","Endpoint":"http://ai-box.invalid:11434/v1","ShareLevel":{"Local":2,"External":1},"ShareLevelNoticePending":true}}""");
        var initial = await _service.LoadAsync();
        Assert.Equal("http://ai-box.invalid:11434/v1", initial.AdvisorEndpoint);
        Assert.True(initial.AdvisorShareLevelNoticePending);

        var saved = await _service.SaveAsync(initial with { LogRetentionDays = 9 }, initial);

        Assert.Equal(9, saved.LogRetentionDays);
        Assert.Equal("http://ai-box.invalid:11434/v1", saved.AdvisorEndpoint);
        // Stufe unverändert: der einmalige Hinweis bleibt, bis der Benutzer ihn bestätigt
        Assert.True(saved.AdvisorShareLevelNoticePending);
        Assert.False((await _service.DismissShareLevelNoticeAsync()).AdvisorShareLevelNoticePending);
    }

    [Fact]
    public async Task StartsWithEverythingOffAndSavesRoundTrip()
    {
        var initial = await _service.LoadAsync();
        Assert.Null(initial.Usage);
        Assert.NotEmpty(initial.Switches);
        Assert.DoesNotContain(true, initial.Switches.Values);

        var switches = initial.Switches.ToDictionary(s => s.Key, s => s.Key is "RegistryMachine" or "NVD" or "CIRCL" or "RestorePoint");
        var saved = await _service.SaveAsync(initial with
        {
            Usage = "Company",
            Switches = switches,
            ScanPaths = ["%USERPROFILE%\\Tools"],
            ScanDrives = ["d"],
            ExcludePaths = ["%USERPROFILE%\\Builds"],
            ComputeHash = true,
            SmartExclusions = false,
            PortableSearch = true,
            TraceSearch = true,
            FileSearch = true,
            ScanMode = "Drives",
            LogRetentionDays = 7,
            LogMaxSizeMB = 50,
            CirclStoreMaxSizeMB = 300,
            CacheHoursCircl = 12,
        });

        var loaded = await _service.LoadAsync();
        foreach (var settings in new[] { saved, loaded })
        {
            Assert.Equal("Company", settings.Usage);
            Assert.Equal(["CIRCL", "NVD", "RegistryMachine", "RestorePoint"], settings.Switches.Where(s => s.Value).Select(s => s.Key).Order());
            Assert.Equal(["%USERPROFILE%\\Tools"], settings.ScanPaths);
            Assert.Equal(["D:"], settings.ScanDrives);
            Assert.Equal(["%USERPROFILE%\\Builds"], settings.ExcludePaths);
            Assert.True(settings.ComputeHash);
            Assert.False(settings.IncludeTemp);
            Assert.False(settings.SmartExclusions);
            Assert.True(settings.PortableSearch);
            Assert.True(settings.TraceSearch);
            Assert.True(settings.FileSearch);
            Assert.Equal("Drives", settings.ScanMode);
            Assert.Equal(7, settings.LogRetentionDays);
            Assert.Equal(50, settings.LogMaxSizeMB);
            Assert.Equal(300, settings.CirclStoreMaxSizeMB);
            Assert.Equal(12, settings.CacheHoursCircl);
        }

        // Alles wieder aus, auch leere Listen werden gespeichert.
        var cleared = await _service.SaveAsync(loaded with { Switches = switches.ToDictionary(s => s.Key, _ => false), ScanPaths = [], ScanDrives = [] });
        Assert.DoesNotContain(true, cleared.Switches.Values);
        Assert.Empty(cleared.ScanPaths);
        Assert.Empty(cleared.ScanDrives);
    }

    [Fact]
    public async Task SavesUsageWithoutTouchingOtherValues()
    {
        var initial = await _service.LoadAsync();
        await _service.SaveAsync(initial with { LogRetentionDays = 12 });

        var saved = await _service.SaveUsageAsync("Private");

        Assert.Equal("Private", saved.Usage);
        Assert.Equal(12, saved.LogRetentionDays);
    }

    [Fact]
    public async Task ReportsModuleValidationErrors()
    {
        var initial = await _service.LoadAsync();

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(() => _service.SaveAsync(initial with { LogRetentionDays = 0 }));
        Assert.Contains("LogRetentionDays", ex.Message);
    }

    [Fact]
    public async Task ReturnsPresetValuesWithoutSaving()
    {
        var preset = await _service.GetPresetAsync("Quick");

        Assert.Contains("Winget", preset.Enable);
        Assert.DoesNotContain("NVD", preset.Enable);
        Assert.Equal(["%USERPROFILE%"], preset.ScanPaths);
        Assert.False(File.Exists(Path.Combine(_directory, "settings.json")));
    }

    [Fact]
    public async Task ReturnsServiceTermsWithoutChangingSettings()
    {
        var company = await _service.GetServiceTermsAsync("Company");

        Assert.Contains(company, t => t.Service == "NVD" && t.Url is not null);
        Assert.Contains(company, t => t.UsageHint is not null);
        Assert.All(company, t => Assert.Contains("bleiben aus", t.General));
        Assert.False(File.Exists(Path.Combine(_directory, "settings.json")));
    }

    [Fact]
    public async Task ListsDrives()
    {
        var drives = await _service.GetDrivesAsync();

        Assert.Contains(drives, d => d.Drive.EndsWith(':') && d.IsDefault);
    }

    [Fact]
    public async Task StoresAndRemovesCredentialsWithoutReturningThem()
    {
        using var secret = new SecureString();
        foreach (var c in "nvd-app-test-key")
        {
            secret.AppendChar(c);
        }

        var stored = await _service.SetCredentialAsync("NVD", secret);
        Assert.True(stored.Stored);
        Assert.Equal("CredentialManager", stored.Source);

        var all = await _service.GetCredentialStatusAsync();
        Assert.Equal(["Advisor", "CIRCL", "GitHub", "NVD"], all.Select(s => s.Service).Order());
        Assert.DoesNotContain("nvd-app-test-key", string.Join(" ", all));

        var removed = await _service.RemoveCredentialAsync("NVD");
        Assert.False(removed.Stored);
    }
}
