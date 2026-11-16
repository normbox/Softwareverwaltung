using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using SoftwareInventory.Helper;

namespace Softwareverwaltung.App.Tests;

/// <summary>
/// Verwaist-Prüfung im Helfer. Die Fälle stehen in tests/Data/registry-orphan-cases.json und gelten ebenso für das Modul
/// (Test-OrphanedRegistryEntry): Beide müssen dasselbe Ergebnis liefern.
/// </summary>
public sealed class OrphanRulesTests
{
    private static string TestFolder([CallerFilePath] string sourceFile = "") => Path.GetDirectoryName(Path.GetDirectoryName(sourceFile)!)!;

    /// <summary>Dateisystem aus der Tabelle nachgebildet; Variablen und Systemordner sind die echten, damit die Platzhalter passen.</summary>
    private sealed class FakeEnvironment : IOrphanEnvironment
    {
        private readonly RealPlaceholders _real = new();
        public HashSet<string> Files { get; } = new(StringComparer.OrdinalIgnoreCase);
        public HashSet<string> Dirs { get; } = new(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, string> Drives { get; } = new(StringComparer.OrdinalIgnoreCase);
        public bool ProfilePathsUnknown { get; set; }

        public string ExpandVariables(string text) => Environment.ExpandEnvironmentVariables(text);
        public bool PathExists(string path) => Files.Contains(path) || Dirs.Contains(path);
        public bool FileExists(string path) => Files.Contains(path);
        public bool RootReachable(string root) => Drives.ContainsKey(root);
        public string DriveType(string root) => Drives.TryGetValue(root, out var type) ? type : null!;
        public bool IsUserProfilePath(string path) => ProfilePathsUnknown && path.StartsWith(@"C:\Users\", StringComparison.OrdinalIgnoreCase);
        public IReadOnlyList<string> SystemFolders => _real.SystemFolders;
        public string SystemFolder => _real.System;
    }

    private sealed class RealPlaceholders
    {
        public string ProgramFiles { get; } = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        public string System { get; } = Environment.GetFolderPath(Environment.SpecialFolder.System);
        public string Windows { get; } = Environment.GetEnvironmentVariable("WINDIR")!;
        public string Root => Path.GetPathRoot(ProgramFiles)!;
        public IReadOnlyList<string> SystemFolders => new[] { System, Environment.GetFolderPath(Environment.SpecialFolder.SystemX86), Windows }.Where(f => !string.IsNullOrEmpty(f)).ToList();

        public string Expand(string? text) => text is null ? null! : Regex.Replace(
            text.Replace("{PF}", ProgramFiles).Replace("{SYS}", System).Replace("{WIN}", Windows).Replace("{ROOT}", Root),
            @"\{U\+([0-9A-Fa-f]{4})\}",
            m => ((char)Convert.ToInt32(m.Groups[1].Value, 16)).ToString());
    }

    private static string? Text(JsonElement c, string name) => c.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    [Fact]
    public void MatchesTheSharedTableWithTheModule()
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(TestFolder(), "Data", "registry-orphan-cases.json")));
        var real = new RealPlaceholders();
        var cases = doc.RootElement.GetProperty("cases").EnumerateArray().ToList();
        Assert.True(cases.Count > 35);

        var wrong = new List<string>();
        foreach (var c in cases)
        {
            var env = new FakeEnvironment();
            foreach (var kind in new[] { ("files", env.Files), ("dirs", env.Dirs) })
            {
                if (c.TryGetProperty(kind.Item1, out var list))
                {
                    foreach (var item in list.EnumerateArray())
                    {
                        kind.Item2.Add(real.Expand(item.GetString()));
                    }
                }
            }
            if (c.TryGetProperty("drives", out var drives))
            {
                foreach (var drive in drives.EnumerateObject())
                {
                    env.Drives[real.Expand(drive.Name)] = drive.Value.GetString()!;
                }
            }
            else
            {
                env.Drives[real.Root] = "Fixed";
            }

            var isMsi = c.TryGetProperty("msi", out var msi) && msi.GetBoolean();
            var reason = OrphanRules.Check(isMsi, real.Expand(Text(c, "uninstall")), real.Expand(Text(c, "quiet")), real.Expand(Text(c, "location")), real.Expand(Text(c, "icon")), env);
            var orphaned = reason is null;
            var expected = c.GetProperty("orphaned").GetBoolean();
            if (orphaned != expected)
            {
                wrong.Add($"{c.GetProperty("name").GetString()}: erwartet {(expected ? "verwaist" : "nicht verwaist")}, Grund {reason ?? "verwaist"}");
            }
        }
        Assert.Empty(wrong);
    }

    [Theory]
    [InlineData(true, "x.exe", "Msi")]
    [InlineData(false, null, "NoUninstallString")]
    [InlineData(false, "   ", "NoUninstallString")]
    [InlineData(false, "setup /x", "CommandUnparseable")]
    public void NamesWhyAnEntryIsNotOrphaned(bool isMsi, string? uninstall, string reason)
    {
        var env = new FakeEnvironment();
        env.Drives[new RealPlaceholders().Root] = "Fixed";
        Assert.Equal(reason, OrphanRules.Check(isMsi, uninstall!, null!, null!, null!, env));
    }

    [Fact]
    public void ADifferentReasonForSystemToolsExistingFilesAndUnknownPaths()
    {
        var real = new RealPlaceholders();
        var env = new FakeEnvironment();
        env.Drives[real.Root] = "Fixed";
        env.Files.Add(real.ProgramFiles + @"\Present\unins.exe");
        Assert.Equal("SystemPath", OrphanRules.Check(false, "msiexec.exe /x {X}", null!, null!, null!, env));
        Assert.Equal("PathExists", OrphanRules.Check(false, "\"" + real.ProgramFiles + "\\Present\\unins.exe\"", null!, null!, null!, env));
        Assert.Equal("PathUnknown", OrphanRules.Check(false, @"Q:\x\unins.exe", null!, null!, null!, env));
        Assert.Null(OrphanRules.Check(false, "\"" + real.ProgramFiles + "\\Gone\\unins.exe\"", null!, null!, null!, env));
    }

    [Fact]
    public void PathsInAUserProfileAreUnknownInTheElevatedHelper()
    {
        var env = new FakeEnvironment { ProfilePathsUnknown = true };
        env.Drives[@"C:\"] = "Fixed";
        Assert.Equal(PathState.Unknown, OrphanRules.GetPathState(@"C:\Users\Anna\AppData\Local\App\app.exe", env));
        Assert.Equal(PathState.Missing, OrphanRules.GetPathState(@"C:\Apps\app.exe", env));
        Assert.Equal("PathUnknown", OrphanRules.Check(false, @"""C:\Users\Anna\AppData\Local\App\unins.exe""", null!, null!, null!, env));
    }

    [Fact]
    public void TheWindowsEnvironmentKnowsFixedDrivesAndTheSystemFolders()
    {
        var env = new WindowsOrphanEnvironment();
        var root = Path.GetPathRoot(Environment.SystemDirectory)!;
        Assert.Equal("Fixed", env.DriveType(root));
        Assert.True(env.RootReachable(root));
        Assert.Null(env.DriveType("not a drive"));
        Assert.Contains(Environment.GetFolderPath(Environment.SpecialFolder.System), env.SystemFolders);
        Assert.True(env.IsUserProfilePath(Path.Combine(root, "Users", "x", "a.exe")));
        Assert.False(env.IsUserProfilePath(Path.Combine(root, "Program Files", "a.exe")));
        Assert.True(env.FileExists(Path.Combine(Environment.SystemDirectory, "cmd.exe")));
        Assert.False(env.FileExists(Path.Combine(Environment.SystemDirectory, "gibt-es-nicht-xyz.exe")));
    }
}
