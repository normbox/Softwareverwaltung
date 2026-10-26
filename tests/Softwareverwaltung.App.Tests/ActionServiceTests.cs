using System.Management.Automation;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;

namespace Softwareverwaltung.App.Tests;

/// <summary>
/// Echtes Modul in der eingebetteten Engine. Es wird nichts ausgeführt: nur -WhatIf und ein Programm,
/// das nicht installiert ist. Der App-Ordner (Protokoll) ist auf ein Testverzeichnis umgelenkt.
/// </summary>
public sealed class ActionServiceTests : IAsyncLifetime
{
    private readonly PowerShellHost _host = new();
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "SoftwareverwaltungTests", Guid.NewGuid().ToString("N"));
    private ActionService _service = null!;

    public async Task InitializeAsync()
    {
        await _host.InitializeAsync();
        Directory.CreateDirectory(_directory);
        var result = await _host.InvokeAsync(new PSCommand().AddScript("""
            param($Dir)
            & (Get-Module SoftwareInventory) {
                param($Dir)
                $script:TestAppData = $Dir
                function script:Get-AppDataDirectory { $script:TestAppData }
                function script:Get-SettingsPath { Join-Path $script:TestAppData 'settings.json' }
            } $Dir
            """).AddParameter("Dir", _directory));
        Assert.Empty(result.Errors);
        _service = new ActionService(_host);
    }

    public Task DisposeAsync()
    {
        _host.Dispose();
        Directory.Delete(_directory, recursive: true);
        return Task.CompletedTask;
    }

    private async Task<PSObject> MissingProgramAsync()
    {
        var result = await _host.InvokeAsync(new PSCommand().AddScript(
            "& (Get-Module SoftwareInventory) { New-SoftwareRecord -Name 'Nicht installiert' -Source Registry -Property @{ RegistryKey = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\SoftwareverwaltungTestFehlt'; Version = '1.0' } }"));
        Assert.Empty(result.Errors);
        return result.Output[0];
    }

    [Fact]
    public async Task ReportsMissingProgramWithoutRunningAnything()
    {
        var plan = await _service.PlanAsync(SoftwareActionKind.Uninstall, await MissingProgramAsync());

        Assert.False(plan.IsPlanned);
        Assert.Equal("NotInstalled", plan.Result);
        Assert.Equal("Uninstall", plan.Action);
    }

    [Fact]
    public async Task PlansWingetInstallationWithWhatIf()
    {
        var plan = await _service.PlanAsync(SoftwareActionKind.InstallWinget, null);

        Assert.True(plan.IsPlanned);
        Assert.Equal("Repair-WinGetPackageManager -Latest", plan.CommandLine);
        Assert.False(plan.Elevated);
    }

    [Fact]
    public async Task RecheckReturnsNullForMissingProgramAndHistoryIsEmpty()
    {
        var missing = await MissingProgramAsync();

        Assert.Null(await _service.RecheckAsync(missing));
        Assert.Empty(await _service.GetHistoryAsync("Nicht [installiert]*"));
    }

    [Fact]
    public async Task ExecuteForMissingProgramRunsNothingButLogsIt()
    {
        var missing = await MissingProgramAsync();
        var fake = new ActionOutcome { Action = "Uninstall", Name = "Nicht installiert", Result = "Planned", CommandLine = "C:\\anders.exe" };

        var outcome = await _service.ExecuteAsync(SoftwareActionKind.Uninstall, missing, fake);

        // Das Programm fehlt: das Modul führt nichts aus, egal welcher Befehl bestätigt wurde.
        Assert.Equal("NotInstalled", outcome.Result);
        var history = await _service.GetHistoryAsync("Nicht installiert");
        Assert.Equal("NotInstalled", Assert.Single(history).Result);
    }
}
