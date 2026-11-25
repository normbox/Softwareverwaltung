using System.Management.Automation;
using Softwareverwaltung.App.Services;

namespace Softwareverwaltung.App.Tests;

/// <summary>Echte eingebettete Engine mit den Modulen aus dem Ausgabeordner, ohne installiertes PowerShell 7.</summary>
public sealed class PowerShellHostTests : IAsyncLifetime
{
    private readonly PowerShellHost _host = new();

    public Task InitializeAsync() => _host.InitializeAsync();

    public Task DisposeAsync()
    {
        _host.Dispose();
        return Task.CompletedTask;
    }

    [Fact]
    public async Task LoadsCoreModuleAndBundledWinGetClient()
    {
        var result = await _host.InvokeAsync(new PSCommand().AddScript(
            "(Get-Module SoftwareInventory).Name; (Get-Module Microsoft.WinGet.Client).Path"));

        Assert.Empty(result.Errors);
        Assert.Equal("SoftwareInventory", result.Output[0].BaseObject);
        // Die mitgelieferte Version, nicht eine eventuell installierte.
        Assert.StartsWith(AppContext.BaseDirectory, (string)result.Output[1].BaseObject, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task EmbeddedEngineRunsWithTelemetryOptOut()
    {
        var result = await _host.InvokeAsync(new PSCommand().AddScript("$env:POWERSHELL_TELEMETRY_OPTOUT"));

        Assert.Equal("1", result.Output.Single().BaseObject);
    }

    [Fact]
    public async Task RunspaceUsesUiCultureOfTheApp()
    {
        var result = await _host.InvokeAsync(new PSCommand().AddScript("$PSUICulture; [cultureinfo]::CurrentCulture.Name"));

        Assert.Empty(result.Errors);
        Assert.Equal(System.Globalization.CultureInfo.CurrentUICulture.Name, result.Output[0].BaseObject);
        Assert.Equal(System.Globalization.CultureInfo.CurrentCulture.Name, result.Output[1].BaseObject);
    }

    [Fact]
    public async Task RunspaceFollowsGivenCultureAndFallsBackToBaseTexts()
    {
        // Andere Sprache als die Basis: Ohne Übersetzung kommen die Basistexte (Deutsch), nie ein Schlüssel.
        var english = System.Globalization.CultureInfo.GetCultureInfo("en-US");
        using var host = new PowerShellHost(uiCulture: english, culture: english);
        await host.InitializeAsync();

        var result = await host.InvokeAsync(new PSCommand().AddScript(
            "$PSUICulture; [cultureinfo]::CurrentCulture.Name; & (Get-Module SoftwareInventory) { (New-InventoryMessage NoFindings).Text }"));

        Assert.Empty(result.Errors);
        Assert.Equal(["en-US", "en-US", "Sicherheitsprüfung ohne Befund"], result.Output.Select(o => o.BaseObject.ToString()));
    }

    [Fact]
    public async Task ModulePathContainsOnlyBundledAndWindowsModules()
    {
        var result = await _host.InvokeAsync(new PSCommand().AddScript("$env:PSModulePath -split [IO.Path]::PathSeparator"));

        Assert.Empty(result.Errors);
        var expected = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "Modules"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "Modules"),
        };
        Assert.Equal(expected, result.Output.Select(o => o.BaseObject.ToString()), StringComparer.OrdinalIgnoreCase);
        Assert.DoesNotContain(result.Output, o => o.BaseObject.ToString()!.Contains(@"\Documents\", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task UserModulesAreNotAutoloaded()
    {
        // Ein Benutzermodul mit eindeutigem Befehl im (vorher üblichen) Dokumente-Pfad darf nicht gefunden werden.
        var result = await _host.InvokeAsync(new PSCommand().AddScript(
            "[bool] (Get-Module -ListAvailable | Where-Object { $_.Path -like '*\\Documents\\*' -or $_.Path -like '*\\Program Files\\PowerShell\\*' })"));

        Assert.Empty(result.Errors);
        Assert.False((bool)result.Output.Single().BaseObject);
    }

    [Fact]
    public async Task ReturnsWingetStatusFromModule()
    {
        var result = await _host.InvokeAsync(new PSCommand().AddCommand("Test-WingetAvailability"));

        Assert.Empty(result.Errors);
        var status = Assert.Single(result.Output);
        Assert.True((bool)status.Properties["ModuleAvailable"].Value);
    }

    [Fact]
    public async Task ReachesWindowsModulesUsedByTheInventory()
    {
        var result = await _host.InvokeAsync(new PSCommand().AddScript(
            "[bool](Get-AppxPackage -ErrorAction Stop | Select-Object -First 1); " +
            "[bool](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop)"));

        Assert.True(result.Errors.Count == 0, string.Join(Environment.NewLine, result.Errors));
        Assert.All(result.Output, o => Assert.True((bool)o.BaseObject));
    }

    [Fact]
    public async Task ReportsErrorsAndWarningsInsteadOfThrowing()
    {
        var result = await _host.InvokeAsync(new PSCommand().AddScript("Write-Warning 'Achtung'; Write-Error 'Kaputt'; 'weiter'"));

        Assert.Equal(["Achtung"], result.Warnings);
        Assert.Contains("Kaputt", Assert.Single(result.Errors));
        Assert.Equal("weiter", Assert.Single(result.Output).BaseObject);
    }

    [Fact]
    public async Task ReportsTerminatingErrors()
    {
        var result = await _host.InvokeAsync(new PSCommand().AddScript("throw 'Abbruch'"));

        Assert.Contains("Abbruch", Assert.Single(result.Errors));
    }

    [Fact]
    public async Task CancelsLongRunningCommands()
    {
        using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(300));

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => _host.InvokeAsync(new PSCommand().AddScript("Start-Sleep -Seconds 30"), cancellationToken: cts.Token));

        // Die Runspace bleibt danach nutzbar.
        var result = await _host.InvokeAsync(new PSCommand().AddScript("1"));
        Assert.Equal(1, Assert.Single(result.Output).BaseObject);
    }

    [Fact]
    public async Task ShutdownStopsRunningCommandWithinTimeout()
    {
        using var host = new PowerShellHost();
        await host.InitializeAsync();
        var key = NewMarkerKey();
        var running = host.InvokeAsync(new PSCommand().AddScript(MarkStarted(key) + "Start-Sleep -Seconds 60"));
        await WaitForMarkerAsync(key);

        var watch = System.Diagnostics.Stopwatch.StartNew();
        var result = host.Shutdown(PowerShellHost.ShutdownTimeout);
        watch.Stop();

        Assert.Equal(ShutdownResult.Stopped, result);
        Assert.True(watch.Elapsed < TimeSpan.FromSeconds(5), $"Beenden dauerte {watch.Elapsed}");
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => running);
    }

    [Fact]
    public async Task ShutdownWithoutRunningCommandIsIdleAndRejectsNewCommands()
    {
        var host = new PowerShellHost();
        await host.InitializeAsync();

        Assert.Equal(ShutdownResult.Idle, host.Shutdown(PowerShellHost.ShutdownTimeout));
        Assert.Equal(ShutdownResult.Idle, host.Shutdown(PowerShellHost.ShutdownTimeout));
        host.Dispose();
        await Assert.ThrowsAsync<ObjectDisposedException>(() => host.InvokeAsync(new PSCommand().AddScript("1")));
    }

    [Fact]
    public async Task ShutdownGivesUpAfterTimeoutAndLeavesOnlyBackgroundThreads()
    {
        // Ein .NET-Aufruf lässt sich von PowerShell nicht unterbrechen: Die Frist läuft ab, die Runspace bleibt offen.
        // Der Thread, auf dem der Befehl läuft, muss ein Hintergrund-Thread sein, sonst endet der Prozess nicht.
        using var host = new PowerShellHost();
        await host.InitializeAsync();
        var key = NewMarkerKey();
        var running = host.InvokeAsync(new PSCommand().AddScript(MarkStarted(key) + "[System.Threading.Thread]::Sleep(4000)"));
        await WaitForMarkerAsync(key);

        var watch = System.Diagnostics.Stopwatch.StartNew();
        var result = host.Shutdown(TimeSpan.FromMilliseconds(500));
        watch.Stop();

        Assert.Equal(ShutdownResult.TimedOut, result);
        Assert.True(watch.Elapsed < TimeSpan.FromSeconds(2), $"Beenden dauerte {watch.Elapsed}");
        Assert.Equal(true, AppDomain.CurrentDomain.GetData(key));
        // Danach hält der Befehl an, sobald der .NET-Aufruf zurückkehrt.
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => running);
    }

    private static string NewMarkerKey() => "PowerShellHostTests." + Guid.NewGuid().ToString("N");

    // Vermerkt beim Start, ob der Befehl auf einem Hintergrund-Thread läuft.
    private static string MarkStarted(string key) =>
        $"[AppDomain]::CurrentDomain.SetData('{key}', [System.Threading.Thread]::CurrentThread.IsBackground); ";

    private static async Task WaitForMarkerAsync(string key)
    {
        var deadline = DateTime.UtcNow.AddSeconds(15);
        while (AppDomain.CurrentDomain.GetData(key) is null)
        {
            Assert.True(DateTime.UtcNow < deadline, "Befehl ist nicht gestartet");
            await Task.Delay(50);
        }
    }

    [Fact]
    public async Task ForwardsProgress()
    {
        var messages = new List<string>();
        var progress = new SynchronousProgress<string>(messages.Add);

        await _host.InvokeAsync(new PSCommand().AddScript("Write-Progress -Activity 'Suche' -Status 'C:\\Programme'"), progress);

        Assert.Contains("Suche: C:\\Programme", messages);
    }

    [Fact]
    public async Task ForwardsCurrentOperationAsSecondLine()
    {
        var messages = new List<string>();
        var progress = new SynchronousProgress<string>(messages.Add);

        await _host.InvokeAsync(new PSCommand().AddScript("Write-Progress -Activity 'Prüfe Sicherheitslücken (3 von 9)' -Status 'Google Chrome' -CurrentOperation 'CIRCL: Seite 37 von 149'"), progress);

        Assert.Contains($"Prüfe Sicherheitslücken (3 von 9): Google Chrome{Environment.NewLine}CIRCL: Seite 37 von 149", messages);
    }

    [Fact]
    public void FormatsProgressWithoutStatusOrOperation()
    {
        Assert.Equal("Suche", PowerShellHost.FormatProgress(new ProgressRecord(1, "Suche", " ")));
        Assert.Equal($"Suche{Environment.NewLine}Schritt", PowerShellHost.FormatProgress(new ProgressRecord(1, "Suche", " ") { CurrentOperation = "Schritt" }));
    }

    private sealed class SynchronousProgress<T>(Action<T> handler) : IProgress<T>
    {
        public void Report(T value) => handler(value);
    }
}
