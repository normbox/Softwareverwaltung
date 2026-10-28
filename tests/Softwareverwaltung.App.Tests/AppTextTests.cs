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

    [Fact]
    public void EveryKeyUsedInCodeExists()
    {
        var used = AppFiles("*.cs")
            .SelectMany(f => CodeKey().Matches(File.ReadAllText(f)).Select(m => m.Groups["key"].Value))
            .Distinct()
            .ToList();

        Assert.NotEmpty(used);
        Assert.All(used, key => Assert.NotNull(AppText.Find(key)));
    }

    [Theory]
    [InlineData("Action", "Update,Uninstall,InstallWinget")]
    [InlineData("ActionResult", "Planned,Succeeded,SucceededRebootRequired,NotVerified,Cancelled,ElevationDenied,NotInstalled,NoUpdateAvailable,ManualUpdateRequired,Unsupported,Timeout,Failed")]
    [InlineData("RestorePoint", "Planned,Created,Skipped,NotAvailable,NotAvailableWithMessage,Failed,FailedWithMessage,None")]
    [InlineData("Assessment", "Affected,PossiblyAffected,Informational")]
    public void EveryCodeHasText(string prefix, string codes)
    {
        Assert.All(codes.Split(','), code => Assert.NotNull(AppText.Find(prefix + code)));
    }

    [Fact]
    public void XamlHasNoFixedTexts()
    {
        // Neue Texte gehören in Strings.resx (CLAUDE.md); Bindungen und {loc:Text …} sind erlaubt.
        var found = AppFiles("*.xaml")
            .SelectMany(f => FixedText().Matches(File.ReadAllText(f)).Select(m => $"{Path.GetFileName(f)}: {m.Value}"))
            .ToList();

        Assert.Empty(found);
    }

    private static IEnumerable<string> AppFiles(string pattern) =>
        Directory.EnumerateFiles(Path.Combine(FindRepositoryRoot(), "src", "Softwareverwaltung.App"), pattern, SearchOption.AllDirectories)
            .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}") && !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"));

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

    // Nur vollständige Schlüssel; zusammengesetzte ("Präfix" + Code) prüft EveryCodeHasText.
    [GeneratedRegex(@"AppText\.(?:Get|Format)\(""(?<key>\w+)""\s*[,)]")]
    private static partial Regex CodeKey();

    [GeneratedRegex(@"(?<=\s)(?:Text|Content|Header|Title|ToolTip|PlaceholderText|OnContent|OffContent|AutomationProperties\.Name)=""[^{""][^""]*\p{L}[^""]*""")]
    private static partial Regex FixedText();
}
