using System.Text.RegularExpressions;
using Softwareverwaltung.App.Localization;

namespace Softwareverwaltung.App.Tests;

public sealed partial class AppTextTests
{
    [Fact]
    public void ReturnsTextForKnownKeyAndKeyForUnknown()
    {
        Assert.Equal("Suche nach portablen Programmen", AppText.Get("SettingsPortableTitle"));
        Assert.Equal("GibtEsNicht", AppText.Get("GibtEsNicht"));
        Assert.Equal("Suche nach portablen Programmen", new TextExtension("SettingsPortableTitle").ProvideValue(null!));
    }

    [Fact]
    public void EveryKeyUsedInXamlExists()
    {
        var root = FindRepositoryRoot();
        var used = Directory.EnumerateFiles(Path.Combine(root, "src", "Softwareverwaltung.App"), "*.xaml", SearchOption.AllDirectories)
            .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}") && !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"))
            .SelectMany(f => LocKey().Matches(File.ReadAllText(f)).Select(m => m.Groups["key"].Value))
            .Distinct()
            .ToList();

        Assert.NotEmpty(used);
        Assert.All(used, key => Assert.NotEqual(key, AppText.Get(key)));
    }

    private static string FindRepositoryRoot([System.Runtime.CompilerServices.CallerFilePath] string sourceFile = "")
    {
        // Vom Ort dieser Quelldatei aus suchen, damit es auch mit einem anderen Ausgabeordner klappt.
        var dir = new DirectoryInfo(Path.GetDirectoryName(sourceFile)!);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "Softwareverwaltung.slnx")))
        {
            dir = dir.Parent;
        }
        return dir?.FullName ?? throw new DirectoryNotFoundException("Repository-Wurzel nicht gefunden.");
    }

    [GeneratedRegex(@"\{loc:Text\s+(?:Key=)?(?<key>\w+)\s*\}")]
    private static partial Regex LocKey();
}
