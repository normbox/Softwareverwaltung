using SoftwareInventory.Helper;
using Softwareverwaltung.App.Models;

namespace Softwareverwaltung.App.Tests;

/// <summary>Prüfungen des Helfers für Administratorrechte; es wird nichts gestartet.</summary>
public sealed class HelperRulesTests
{
    private static HelperPaths Paths(params string[] existing) => new()
    {
        ProgramFiles = @"C:\Program Files",
        SystemDrive = "C:",
        Windows = @"C:\Windows",
        TempPath = @"C:\Users\a\AppData\Local\Temp\",
        System32 = @"C:\Windows\System32",
        FileExists = p => existing.Contains(p, StringComparer.OrdinalIgnoreCase),
    };

    private const string Winget = @"C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1_x64__8\winget.exe";
    private const string Msi = @"C:\Windows\System32\msiexec.exe";
    private const string Key = @"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\App";

    [Fact]
    public void AcceptsProgramsOutsideUserAndTempFolders()
    {
        Assert.Null(HelperRules.CheckFilePath(Msi, true, Paths(Msi)));
    }

    [Theory]
    [InlineData(@"C:\Users\Public\x.exe", "HelperPathInUserFolder")]
    [InlineData(@"C:\Windows\Temp\x.exe", "HelperPathInUserFolder")]
    [InlineData(@"C:\Users\a\AppData\Local\Temp\x.exe", "HelperPathInUserFolder")]
    [InlineData("x.exe", "HelperPathNotAbsolute")]
    [InlineData("", "HelperPathNotAbsolute")]
    [InlineData(@"C:\Users\a\AppData\Local\Microsoft\WindowsApps\winget.exe", "HelperWingetNotFound")]
    [InlineData(@"C:\Program Files\App\fehlt.exe", "HelperFileNotFound")]
    public void RefusesUnsafeOrMissingFilesWhenElevated(string path, string code)
    {
        Assert.Equal(code, HelperRules.CheckFilePath(path, true, Paths())!.Code);
    }

    [Fact]
    public void ProgramsInTheUserFolderRunOnlyWithoutElevation()
    {
        const string exe = @"C:\Users\a\AppData\Local\Programs\App\unins000.exe";
        Assert.Equal("HelperPathInUserFolder", HelperRules.CheckFilePath(exe, true, Paths(exe))!.Code);
        Assert.Null(HelperRules.CheckFilePath(exe, false, Paths(exe)));
    }

    [Fact]
    public void WingetIsAcceptedOnlyFromWindowsApps()
    {
        Assert.Null(HelperRules.CheckFilePath(Winget, true, Paths(Winget)));
    }

    [Fact]
    public void WithoutElevationTheCommandIsNotRestricted()
    {
        Assert.Null(HelperRules.CheckCommand("Irgendwas", @"C:\x.exe", "/y", null!, false, Paths(), (_, _) => null!));
    }

    [Theory]
    [InlineData("Winget", Winget, "upgrade --id A.B --exact --source winget", true)]
    [InlineData("Winget", Winget, "uninstall --id A.B --exact", true)]
    [InlineData("Winget", Winget, "install --id A.B", false)]
    [InlineData("Winget", @"C:\Tools\evil.exe", "upgrade --id A.B", false)]
    [InlineData("Msi", Msi, "/x {11111111-2222-3333-4444-555555555555} /qn /norestart", true)]
    [InlineData("Msi", Msi, "/i C:\\boese.msi /qn", false)]
    [InlineData("Msi", @"C:\Tools\msiexec.exe", "/x {11111111-2222-3333-4444-555555555555} /qn /norestart", false)]
    [InlineData("Unbekannt", Msi, "", false)]
    [InlineData(null, Msi, "", false)]
    public void ElevatedWingetAndMsiOnlyInTheirFixedForm(string? method, string file, string arguments, bool allowed)
    {
        var problem = HelperRules.CheckCommand(method!, file, arguments, null!, true, Paths(), (_, _) => null!);

        Assert.Equal(allowed, problem is null);
        if (!allowed)
        {
            Assert.Equal("HelperCommandMismatch", problem!.Code);
        }
    }

    [Theory]
    [InlineData("\"C:\\Program Files\\App\\unins000.exe\" /SILENT", @"C:\Program Files\App\unins000.exe", "/SILENT", true)]
    [InlineData(@"C:\Program Files\App\uninst.exe /S", @"C:\Program Files\App\uninst.exe", "/S", true)]
    [InlineData(@"MsiExec.exe /X{ABC}", @"C:\Windows\System32\MsiExec.exe", "/X{ABC}", true)]
    [InlineData("\"C:\\Program Files\\App\\unins000.exe\"", @"C:\Program Files\App\unins000.exe", "", true)]
    [InlineData("\"C:\\Program Files\\App\\unins000.exe\" /SILENT", @"C:\Program Files\App\unins000.exe", "/SILENT /EVIL", false)]
    [InlineData("\"C:\\Program Files\\App\\unins000.exe\" /SILENT", @"C:\Program Files\Other\unins000.exe", "/SILENT", false)]
    [InlineData(@"MsiExec.exe /X{ABC}", @"C:\Tools\MsiExec.exe", "/X{ABC}", false)]
    [InlineData("", @"C:\x.exe", "", false)]
    public void UninstallCommandMustMatchTheRegistryValue(string raw, string file, string arguments, bool expected)
    {
        Assert.Equal(expected, HelperRules.CommandMatches(raw, file, arguments, Paths()));
    }

    [Fact]
    public void UninstallCommandIsReadFromTheRegistryNotFromThePlan()
    {
        const string file = @"C:\Program Files\App\uninst.exe";
        string? askedKey = null;
        string? askedValue = null;

        var ok = HelperRules.CheckCommand("QuietUninstallString", file, "/S", Key, true, Paths(), (k, v) =>
        {
            askedKey = k;
            askedValue = v;
            return "\"" + file + "\" /S";
        });
        var forged = HelperRules.CheckCommand("UninstallString", @"C:\Tools\evil.exe", "/S", Key, true, Paths(), (_, _) => "\"" + file + "\" /S");

        Assert.Null(ok);
        Assert.Equal(Key, askedKey);
        Assert.Equal("QuietUninstallString", askedValue);
        Assert.Equal("HelperCommandMismatch", forged!.Code);
    }

    [Theory]
    [InlineData(@"HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\App")]
    [InlineData(@"HKLM:\SOFTWARE\Evil\App")]
    [InlineData(@"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\App\Sub")]
    [InlineData("")]
    public void ElevatedUninstallAcceptsOnlyKeysDirectlyBelowHklmUninstall(string key)
    {
        var problem = HelperRules.CheckCommand("UninstallString", @"C:\x.exe", "", key, true, Paths(), (_, _) => @"C:\x.exe");

        Assert.Equal("HelperCommandMismatch", problem!.Code);
    }

    [Fact]
    public void WowKeysAreAccepted()
    {
        const string wow = @"HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Foxit Reader_is1";
        Assert.Null(HelperRules.CheckCommand("UninstallString", @"C:\x.exe", "", wow, true, Paths(), (_, _) => @"C:\x.exe"));
    }

    [Fact]
    public void OutputTailRemovesProgressBarsAndSpinners()
    {
        const string text = "Gefunden 7-Zip [7zip.7zip]\r\n   -\r   \\\r   |\r\n  ██████▒▒▒▒  1.2 MB / 2.0 MB\r\nErfolgreich installiert\r\n";

        Assert.Equal("Gefunden 7-Zip [7zip.7zip]\nErfolgreich installiert", HelperRules.OutputTail(text));
    }

    [Fact]
    public void OutputTailKeepsOnlyTheLastLines()
    {
        Assert.Equal("b\nc", HelperRules.OutputTail("a\nb\nc", 2));
        Assert.Null(HelperRules.OutputTail(""));
    }

    private sealed class FakeTarget : ICancelTarget
    {
        public int Id => 42;
        public int Killed { get; private set; }
        public void Kill() => Killed++;
        public bool WaitForExit(int milliseconds) => true;
    }

    [Fact]
    public void CancelNeverStopsAnythingButWinget()
    {
        var target = new FakeTarget();
        Assert.Equal(CancelRules.Continuing, CancelRules.Request(Msi, target, _ => []));
        Assert.Equal(0, target.Killed);
    }

    [Fact]
    public void CancelDoesNotStopWingetOnceAnInstallerRuns()
    {
        var target = new FakeTarget();
        Assert.Equal(CancelRules.Continuing, CancelRules.Request(Winget, target, _ => ["conhost.exe", "setup.exe"]));
        Assert.Equal(0, target.Killed);
    }

    [Fact]
    public void CancelStopsWingetWhileOnlyConhostIsAChild()
    {
        var target = new FakeTarget();
        Assert.Equal(CancelRules.Stopped, CancelRules.Request(Winget, target, _ => ["conhost.exe"]));
        Assert.Equal(1, target.Killed);
    }

    [Fact]
    public void CancelReportsAnInstallerThatStartedJustInTime()
    {
        var queries = 0;
        Assert.Equal(CancelRules.Orphaned, CancelRules.Request(Winget, new FakeTarget(), _ => ++queries > 1 ? ["setup.exe"] : []));
    }

    [Fact]
    public void CancelLeavesTheActionRunningWhenTheCheckFails()
    {
        var target = new FakeTarget();
        Assert.Equal(CancelRules.Continuing, CancelRules.Request(Winget, target, _ => throw new InvalidOperationException()));
        Assert.Equal(0, target.Killed);
    }

    private sealed class FakeRestore : IRestorePointApi
    {
        public Func<long> Latest { get; set; } = () => 5;
        public Func<long> CreateResult { get; set; } = () => 0;
        public bool Disabled { get; set; }
        public long LatestSequence() => Latest();
        public long Create(string description, uint type) => CreateResult();
        public bool ProtectionDisabled() => Disabled;
    }

    [Fact]
    public void RestorePointIsCreatedWhenTheSequenceGrows()
    {
        long sequence = 5;
        var api = new FakeRestore { Latest = () => sequence, CreateResult = () => { sequence = 6; return 0; } };

        var outcome = RestorePointRules.Run(api, "Test", 1);

        Assert.Equal("Created", outcome.Status);
        Assert.Equal("RestorePointCreatedNumber", outcome.Code);
    }

    [Fact]
    public void RestorePointSkippedWhenWindowsCreatesNone()
    {
        var outcome = RestorePointRules.Run(new FakeRestore(), "Test", 1);
        Assert.Equal("Skipped", outcome.Status);
        Assert.Equal("RestorePointNotCreated", outcome.Code);
    }

    [Fact]
    public void RestorePointNotAvailableWhenProtectionIsOff()
    {
        Assert.Equal("RestorePointProtectionDisabled", RestorePointRules.Run(new FakeRestore { Disabled = true }, "T", 1).Code);
        Assert.Equal("RestorePointProtectionOff", RestorePointRules.Run(new FakeRestore { CreateResult = () => 1058 }, "T", 1).Code);
    }

    [Fact]
    public void RestorePointNotAvailableWhenServiceIsDisabledAsException()
    {
        var api = new FakeRestore { CreateResult = () => throw new RestorePointApiException("Dienst deaktiviert", [-2147023838]) };

        var outcome = RestorePointRules.Run(api, "T", 1);

        Assert.Equal("NotAvailable", outcome.Status);
        Assert.Equal("RestorePointProtectionOffDetail", outcome.Code);
    }

    [Fact]
    public void RestorePointFailedNamesTheCode()
    {
        var api = new FakeRestore { CreateResult = () => throw new RestorePointApiException("anders", [-2147024891]) };

        var outcome = RestorePointRules.Run(api, "T", 1);

        Assert.Equal("Failed", outcome.Status);
        Assert.Equal("RestorePointFailedDetail", outcome.Code);
        Assert.Contains("0x80070005", (string)outcome.Args[1]);
        Assert.Equal("RestorePointFailedCode", RestorePointRules.Run(new FakeRestore { CreateResult = () => 5 }, "T", 1).Code);
    }

    [Fact]
    public void RestorePointNotAvailableWhenTheClassIsMissing()
    {
        var api = new FakeRestore { Latest = () => throw new InvalidOperationException("Ungültige Klasse") };
        Assert.Equal("RestorePointServiceUnavailable", RestorePointRules.Run(api, "T", 1).Code);
    }

    [Theory]
    [InlineData(true, true, true)]
    [InlineData(false, true, false)]
    [InlineData(true, false, false)]
    public void QueueWarnsOnlyForElevatedEntriesFromAWritableFolder(bool elevated, bool writable, bool expected)
    {
        var entry = new QueueEntry(0, "A", "1", "2", false, true, elevated, "cmd", null, new System.Management.Automation.PSObject()) { HelperInWritableFolder = writable };

        Assert.Equal(expected, new QueueConfirmation([entry]).ShowHelperWarning);
    }
}
