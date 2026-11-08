using SoftwareInventory.Helper;
using Xunit;

namespace Softwareverwaltung.App.Tests;

public sealed class HelperCopyRulesTests
{
    private const string Pf = @"C:\Program Files";
    private const string Own = @"C:\Program Files\Softwareverwaltung\Helper\0.1.0\SoftwareInventory.Helper.exe";
    private const string Source = @"D:\App\Modules\SoftwareInventory\lib\SoftwareInventory.Helper.exe";

    [Theory]
    [InlineData(Own, true)]
    [InlineData(@"D:\App\SoftwareInventory.Helper.exe", false)]
    [InlineData(@"C:\Program Files\Softwareverwaltung\Helper\SoftwareInventory.Helper.exe", false)]
    [InlineData(@"C:\Program Files\Softwareverwaltung\Helper\neu\SoftwareInventory.Helper.exe", false)]
    [InlineData(@"C:\Program Files\Softwareverwaltung\Helper\0.1.0\anders.exe", false)]
    public void RecognizesOnlyTheProtectedStructure(string path, bool expected) =>
        Assert.Equal(expected, HelperCopyRules.CopyRoot(path, Pf) is not null);

    [Fact]
    public void RemovesOnlyOlderVersionFolders()
    {
        var folders = new[] { @"R:\0.0.9", @"R:\0.1.0", @"R:\0.2.0", @"R:\fremd" };
        Assert.Equal([@"R:\0.0.9"], HelperCopyRules.OlderSiblings("0.1.0", folders));
    }

    [Fact]
    public void ReplaceNeedsTheProtectedExe() =>
        Assert.Equal("HelperCopyNotProtected", HelperCopyRules.CheckReplace(Source, Pf, Source, "0.2.0", "CN=A", "CN=A").Code);

    [Theory]
    [InlineData("..\\..\\Windows")]
    [InlineData("neu")]
    [InlineData(null)]
    public void ReplaceRejectsInvalidVersions(string? version) =>
        Assert.Equal("HelperCopyInvalidVersion", HelperCopyRules.CheckReplace(Own, Pf, Source, version!, "CN=A", "CN=A").Code);

    [Fact]
    public void ReplaceRejectsAnotherFile() =>
        Assert.Equal("HelperCopyUntrusted", HelperCopyRules.CheckReplace(Own, Pf, @"D:\boese.exe", "0.2.0", "CN=A", "CN=A").Code);

    [Theory]
    [InlineData(null, "CN=A")]
    [InlineData("CN=A", null)]
    [InlineData("", "")]
    public void ReplaceNeedsValidSignatures(string? own, string? source) =>
        Assert.Equal("HelperCopyUntrusted", HelperCopyRules.CheckReplace(Own, Pf, Source, "0.2.0", own!, source!).Code);

    [Fact]
    public void ReplaceRejectsAnotherPublisher() =>
        Assert.Equal("HelperCopyPublisherMismatch", HelperCopyRules.CheckReplace(Own, Pf, Source, "0.2.0", "CN=A", "CN=B").Code);

    [Fact]
    public void ReplaceAcceptsTheSamePublisher() =>
        Assert.Null(HelperCopyRules.CheckReplace(Own, Pf, Source, "0.2.0", "CN=A", "CN=A"));
}
