using System.Management.Automation;
using System.Security;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;

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
        await _host.InitializeAsync();
        Directory.CreateDirectory(_directory);
        // Nur in dieser Runspace: Funktion und Variable im Modulbereich ersetzen.
        var result = await _host.InvokeAsync(new PSCommand().AddScript("""
            param($File, $Prefix)
            & (Get-Module SoftwareInventory) {
                param($File, $Prefix)
                $script:TestSettingsFile = $File
                function script:Get-SettingsPath { $script:TestSettingsFile }
                $script:CredentialPrefix = $Prefix
            } $File $Prefix
            """).AddParameter("File", Path.Combine(_directory, "settings.json")).AddParameter("Prefix", _prefix));
        Assert.Empty(result.Errors);
        _service = new SettingsService(_host);
    }

    public async Task DisposeAsync()
    {
        await _service.RemoveCredentialAsync("NVD");
        await _service.RemoveCredentialAsync("GitHub");
        _host.Dispose();
        Directory.Delete(_directory, recursive: true);
    }

    [Fact]
    public async Task StartsWithEverythingOffAndSavesRoundTrip()
    {
        var initial = await _service.LoadAsync();
        Assert.Null(initial.Usage);
        Assert.NotEmpty(initial.Switches);
        Assert.DoesNotContain(true, initial.Switches.Values);

        var switches = initial.Switches.ToDictionary(s => s.Key, s => s.Key is "RegistryMachine" or "NVD" or "RestorePoint");
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
            LogRetentionDays = 7,
            LogMaxSizeMB = 50,
        });

        var loaded = await _service.LoadAsync();
        foreach (var settings in new[] { saved, loaded })
        {
            Assert.Equal("Company", settings.Usage);
            Assert.Equal(["NVD", "RegistryMachine", "RestorePoint"], settings.Switches.Where(s => s.Value).Select(s => s.Key).Order());
            Assert.Equal(["%USERPROFILE%\\Tools"], settings.ScanPaths);
            Assert.Equal(["D:"], settings.ScanDrives);
            Assert.Equal(["%USERPROFILE%\\Builds"], settings.ExcludePaths);
            Assert.True(settings.ComputeHash);
            Assert.False(settings.IncludeTemp);
            Assert.False(settings.SmartExclusions);
            Assert.True(settings.PortableSearch);
            Assert.Equal(7, settings.LogRetentionDays);
            Assert.Equal(50, settings.LogMaxSizeMB);
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
        Assert.Equal(["Advisor", "GitHub", "NVD"], all.Select(s => s.Service).Order());
        Assert.DoesNotContain("nvd-app-test-key", string.Join(" ", all));

        var removed = await _service.RemoveCredentialAsync("NVD");
        Assert.False(removed.Stored);
    }
}
