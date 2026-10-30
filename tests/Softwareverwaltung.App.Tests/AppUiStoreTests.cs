using System.IO;
using Softwareverwaltung.App.Services;

namespace Softwareverwaltung.App.Tests;

public sealed class AppUiStoreTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "app-ui-" + Guid.NewGuid().ToString("N"));

    private string FilePath => Path.Combine(_dir, "app-ui.json");

    public void Dispose()
    {
        if (Directory.Exists(_dir))
        {
            Directory.Delete(_dir, recursive: true);
        }
    }

    [Fact]
    public void StartsWithFortyPercentWithoutFile()
    {
        Assert.Equal(0.4, new AppUiStore(FilePath).Load().DetailsWidthFraction);
    }

    [Fact]
    public void SavesAndLoadsTheWidth()
    {
        var store = new AppUiStore(FilePath);
        store.Save(new AppUiSettings { DetailsWidthFraction = 0.55 });

        Assert.True(File.Exists(FilePath));
        Assert.Equal(0.55, new AppUiStore(FilePath).Load().DetailsWidthFraction);
    }

    [Theory]
    [InlineData("{\"DetailsWidthFraction\": 5}", 0.9)]
    [InlineData("{\"DetailsWidthFraction\": 0.01}", 0.15)]
    [InlineData("kein JSON", 0.4)]
    public void LimitsOrIgnoresInvalidValues(string content, double expected)
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(FilePath, content);

        Assert.Equal(expected, new AppUiStore(FilePath).Load().DetailsWidthFraction);
    }
}
