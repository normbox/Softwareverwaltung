using SoftwareInventory.Helper;

namespace Softwareverwaltung.App.Tests;

[CollectionDefinition("ProcessEnvironment", DisableParallelization = true)]
public sealed class ProcessEnvironmentCollection
{
}

/// <summary>
/// Der erhöhte Helfer setzt nur maschinenweite Variablen ein, mit Werten aus Windows-Funktionen statt aus der Umgebung des
/// Prozesses (die kommt auch aus HKCU\Environment). Jede andere Variable macht einen Pfad nicht auswertbar.
/// </summary>
[Collection("ProcessEnvironment")]
public sealed class MachineFoldersTests
{
    private static MachineFolders Sample() => new(new Dictionary<string, string>
    {
        ["ProgramFiles"] = @"C:\Program Files\",
        ["ProgramFiles(x86)"] = @"C:\Program Files (x86)",
        ["SystemRoot"] = @"C:\Windows",
        ["SystemDrive"] = @"C:\",
        ["USERPROFILE"] = @"C:\Users\Anna",
    });

    [Theory]
    [InlineData(@"%ProgramFiles%\App\a.exe", @"C:\Program Files\App\a.exe")]
    [InlineData(@"%programfiles(X86)%\App\a.exe", @"C:\Program Files (x86)\App\a.exe")]
    [InlineData(@"%SystemDrive%\Apps\a.exe", @"C:\Apps\a.exe")]
    [InlineData(@"%SystemRoot%\x.exe", @"C:\Windows\x.exe")]
    [InlineData(@"C:\Apps\a.exe", @"C:\Apps\a.exe")]
    [InlineData(@"C:\100% sicher\a.exe", @"C:\100% sicher\a.exe")]
    public void ExpandsOnlyMachineWideVariables(string text, string expected)
    {
        Assert.Equal(expected, Sample().Expand(text));
    }

    [Theory]
    [InlineData(@"%USERPROFILE%\a.exe")]
    [InlineData(@"%LOCALAPPDATA%\App\a.exe")]
    [InlineData(@"%ProgramFiles%\%APPNAME%\a.exe")]
    [InlineData(@"%windir%\x.exe")]
    public void AnyOtherOrMissingVariableMakesThePathUnusable(string text)
    {
        // USERPROFILE steht zwar in der Eingabe, ist aber nicht erlaubt; windir fehlt im Beispiel ganz.
        Assert.Null(Sample().Expand(text));
    }

    [Fact]
    public void UnusableVariablesMakeThePathUnknownNeverMissing()
    {
        var env = new WindowsOrphanEnvironment(Sample());
        Assert.Equal(PathState.Unknown, OrphanRules.GetPathState(@"%USERPROFILE%\Gone\a.exe", env));
        Assert.Equal("CommandUnparseable", OrphanRules.Check(false, @"""%APPDATA%\Gone\unins.exe""", null!, null!, null!, env));
        Assert.Equal("CommandUnparseable", OrphanRules.Check(false, @"%APPDATA%\Gone\unins.exe /S", null!, null!, null!, env));
    }

    [Fact]
    public void AnIconWithAnUnusableVariableCountsAsUnknownNotAsAbsent()
    {
        var env = new WindowsOrphanEnvironment(Sample());
        var gone = @"""C:\Program Files\Gone-" + Guid.NewGuid().ToString("N") + @"\unins.exe""";
        Assert.Null(OrphanRules.Check(false, gone, null!, null!, null!, env));
        Assert.Equal("PathUnknown", OrphanRules.Check(false, gone, null!, null!, @"%APPDATA%\App\app.ico,0", env));
    }

    [Fact]
    public void TheValuesComeFromWindowsNotFromTheProcessEnvironment()
    {
        var names = new[] { "ProgramFiles", "ProgramW6432", "CommonProgramFiles", "SystemRoot", "windir", "ProgramData" };
        var saved = names.ToDictionary(n => n, Environment.GetEnvironmentVariable);
        try
        {
            foreach (var name in names)
            {
                Environment.SetEnvironmentVariable(name, @"C:\Nix");
            }
            var folders = MachineFolders.Current();
            foreach (var name in MachineFolders.Names)
            {
                Assert.False(string.IsNullOrEmpty(folders[name]), name);
                Assert.NotEqual(@"C:\Nix", folders[name]);
            }
            Assert.Equal(Path.GetPathRoot(Environment.SystemDirectory)!.TrimEnd('\\'), folders["SystemDrive"]);
            Assert.Equal(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), folders["ProgramFiles"]);
            Assert.Null(new WindowsOrphanEnvironment().ExpandVariables(@"%USERPROFILE%\x"));
            Assert.DoesNotContain(@"C:\Nix", new WindowsOrphanEnvironment().NativeProgramFolders);
            Assert.DoesNotContain(@"C:\Nix", new WindowsOrphanEnvironment().SystemFolders);
        }
        finally
        {
            foreach (var pair in saved)
            {
                Environment.SetEnvironmentVariable(pair.Key, pair.Value);
            }
        }
    }
}
