using System.Management.Automation;
using System.Runtime.CompilerServices;
using Softwareverwaltung.App.Services;

namespace Softwareverwaltung.App.Tests;

/// <summary>
/// Scan mit dem echten Modul. Einstellungen und App-Ordner sind auf Testverzeichnisse umgelenkt.
/// Der Scan-Ordner liegt bewusst nicht unter Temp, weil der Dateiscan Temp standardmäßig auslässt.
/// </summary>
public sealed class InventoryServiceTests : IAsyncLifetime
{
    private readonly PowerShellHost _host = new();
    private readonly string _appData = Path.Combine(Path.GetTempPath(), "SoftwareverwaltungTests", Guid.NewGuid().ToString("N"));
    private readonly string _scanFolder = Path.Combine(TestFolder(), "obj", "portable-scan-" + Guid.NewGuid().ToString("N"));
    private InventoryService _service = null!;

    public async Task InitializeAsync()
    {
        await _host.InitializeAsync();
        Directory.CreateDirectory(_appData);
        var result = await _host.InvokeAsync(new PSCommand().AddScript("""
            param($Dir)
            & (Get-Module SoftwareInventory) {
                param($Dir)
                $script:TestAppData = $Dir
                function script:Get-AppDataDirectory { $script:TestAppData }
                function script:Get-SettingsPath { Join-Path $script:TestAppData 'settings.json' }
            } $Dir
            """).AddParameter("Dir", _appData));
        Assert.Empty(result.Errors);
        _service = new InventoryService(_host);
    }

    public Task DisposeAsync()
    {
        _host.Dispose();
        Directory.Delete(_appData, recursive: true);
        if (Directory.Exists(_scanFolder))
        {
            Directory.Delete(_scanFolder, recursive: true);
        }
        return Task.CompletedTask;
    }

    [Fact]
    public async Task WithoutPortableSearchThereIsNoPortableWarning()
    {
        var result = await _service.ScanAsync();

        Assert.DoesNotContain(result.Warnings, w => w.Contains("Scan-Ordner", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(result.Items, i => i.Sources.Contains("Portable"));
    }

    [Fact]
    public async Task FindsPortableProgramsInConfiguredFolder()
    {
        Directory.CreateDirectory(_scanFolder);
        File.Copy(Path.Combine(Environment.SystemDirectory, "whoami.exe"), Path.Combine(_scanFolder, "whoami.exe"));
        var set = await _host.InvokeAsync(new PSCommand().AddCommand("Set-InventorySetting").AddParameter("ScanPath", new[] { _scanFolder }));
        Assert.Empty(set.Errors);

        var result = await _service.ScanAsync();

        var portable = Assert.Single(result.Items, i => i.Sources.Contains("Portable"));
        Assert.StartsWith(_scanFolder, portable.InstallLocation, StringComparison.OrdinalIgnoreCase);
    }

    private static string TestFolder([CallerFilePath] string sourceFile = "") => Path.GetDirectoryName(sourceFile)!;
}
