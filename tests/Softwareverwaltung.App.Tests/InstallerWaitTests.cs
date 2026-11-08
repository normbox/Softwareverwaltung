using System.Management.Automation;
using System.Threading;
using SoftwareInventory;
using Softwareverwaltung.App.Models;
using Xunit;

namespace Softwareverwaltung.App.Tests;

public sealed class InstallerWaitTests
{
    [Fact]
    public void MutexNotPresentMeansFree() =>
        Assert.False(InstallerActivity.IsBusy(() => throw new WaitHandleCannotBeOpenedException()));

    [Fact]
    public void AccessDeniedCountsAsStillRunning() =>
        Assert.True(InstallerActivity.IsBusy(() => throw new UnauthorizedAccessException()));

    [Fact]
    public void OpenedMutexMeansBusy() => Assert.True(InstallerActivity.IsBusy(() => { }));

    [Theory]
    [InlineData("Portable", null, false)]
    [InlineData("Portable", "A.B", true)]
    [InlineData("Machine", null, true)]
    [InlineData(null, null, true)]
    public void PortableProgramsOfferTheFolderInsteadOfUninstall(string? installType, string? wingetId, bool showUninstall)
    {
        var item = new SoftwareItem { Name = "App", InstallType = installType, WingetId = wingetId };
        Assert.Equal(showUninstall, item.ShowUninstall);
        Assert.Equal(!showUninstall, item.ShowOpenFolderInsteadOfUninstall);
    }

    [Fact]
    public void StatusNamesTheWindowsInstaller() =>
        Assert.Contains("Windows Installer", ActionProgress.StatusText("Update", "App", ActionProgress.WaitingForInstaller, null, false, TimeSpan.Zero));

    [Theory]
    [InlineData("NotVerifiedInstallerBusy", true)]
    [InlineData("NotVerifiedWaitCancelled", true)]
    [InlineData("NotVerifiedUpdate", false)]
    public void OffersRecheckOnlyWhileTheResultIsOpen(string code, bool expected)
    {
        var message = new PSObject();
        message.Properties.Add(new PSNoteProperty("Code", code));
        message.Properties.Add(new PSNoteProperty("Text", "Text"));
        var result = new PSObject();
        result.Properties.Add(new PSNoteProperty("Action", "Update"));
        result.Properties.Add(new PSNoteProperty("Name", "App"));
        result.Properties.Add(new PSNoteProperty("Result", "NotVerified"));
        result.Properties.Add(new PSNoteProperty("Message", message));

        var outcome = ActionOutcome.FromPs(result);

        Assert.Equal(code, outcome.MessageCode);
        Assert.Equal(expected, outcome.OfferRecheck);
    }

    [Theory]
    [InlineData("ElevationDenied", "NotRequested", false)]
    [InlineData("ElevationDenied", null, false)]
    [InlineData("ElevationDenied", "Failed", true)]
    [InlineData("Succeeded", "NotRequested", true)]
    public void HidesRestorePointLineWhenUacWasDenied(string result, string? restorePoint, bool expected) =>
        Assert.Equal(expected, new ActionOutcome { Action = "Update", Name = "App", Result = result, RestorePoint = restorePoint }.ShowRestorePoint);
}
