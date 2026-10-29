using System.Xml.Linq;

namespace Softwareverwaltung.App.Tests;

/// <summary>Bestätigungen vor Aktionen: Enter allein darf nichts ausführen (Standard-Button „Abbrechen“).</summary>
public sealed class ConfirmWindowTests
{
    [Theory]
    [InlineData("ConfirmActionWindow.xaml")]
    [InlineData("QueueConfirmWindow.xaml")]
    [InlineData("StoreAgreementWindow.xaml")]
    [InlineData("CpeMappingWindow.xaml")]
    public void CancelIsTheDefaultButton(string file)
    {
        var path = Path.Combine(RepositoryRoot(), "src", "Softwareverwaltung.App", "Views", file);
        var buttons = XDocument.Load(path).Descendants().Where(e => e.Name.LocalName == "Button").ToList();
        var defaults = buttons.Where(b => (string?)b.Attribute("IsDefault") == "True").ToList();

        var only = Assert.Single(defaults);
        Assert.Equal("True", (string?)only.Attribute("IsCancel"));
        Assert.Contains("CommonCancel", (string?)only.Attribute("Content"));
    }

    private static string RepositoryRoot([System.Runtime.CompilerServices.CallerFilePath] string sourceFile = "")
    {
        var dir = new DirectoryInfo(Path.GetDirectoryName(sourceFile)!);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "Softwareverwaltung.slnx")))
        {
            dir = dir.Parent;
        }
        return dir?.FullName ?? throw new DirectoryNotFoundException();
    }
}
