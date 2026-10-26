using Softwareverwaltung.App.Services;
using static Softwareverwaltung.App.Tests.TestHelpers;

namespace Softwareverwaltung.App.Tests;

public sealed class DriveChangeWatcherTests
{
    [Fact]
    public void SeveralNotificationsInARowRaiseOneChange() => RunOnDispatcher(async () =>
    {
        var watcher = new DriveChangeWatcher();
        var count = 0;
        watcher.DrivesChanged += (_, _) => count++;

        watcher.NotifyChanged();
        watcher.NotifyChanged();
        watcher.NotifyChanged();
        await Task.Delay(1500);

        Assert.Equal(1, count);
    });
}
