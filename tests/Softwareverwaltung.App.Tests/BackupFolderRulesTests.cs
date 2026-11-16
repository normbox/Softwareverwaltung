using System.Diagnostics;
using SoftwareInventory.Helper;

namespace Softwareverwaltung.App.Tests;

/// <summary>
/// Ordner für HKLM-Sicherungen: nur Administratoren dürfen schreiben, kein Reparse-Point, vertrauenswürdiger
/// Besitzer, bei jeder Nutzung und für jede Pfadkomponente. Die Regeln laufen gegen einen Adapter; die echten
/// ACLs prüft nur der kurze Test am Ende (ohne Adminrechte lassen sich keine Admin-ACLs anlegen).
/// </summary>
public sealed class BackupFolderRulesTests
{
    private const string ProgramFiles = @"C:\Program Files";
    private const string Folder = @"C:\Program Files\Softwareverwaltung\RegistryBackup";
    private const string Users = "S-1-5-32-545";
    private const string AuthenticatedUsers = "S-1-5-11";
    private const string Everyone = "S-1-1-0";
    private const string CurrentUser = "S-1-5-21-1-2-3-1001";

    private sealed class FakeInspector : IDirectoryInspector
    {
        public Dictionary<string, (bool Reparse, string? Owner, string[] Writers)> Dirs { get; } = new(StringComparer.OrdinalIgnoreCase);

        /// <summary>Wird beim Lesen des Besitzers geworfen (Rechte nicht lesbar).</summary>
        public Exception? Failure { get; set; }

        public static FakeInspector Trusted()
        {
            var fake = new FakeInspector();
            foreach (var path in new[] { @"C:\Program Files\Softwareverwaltung", Folder })
            {
                fake.Dirs[path] = (false, BackupFolderRules.AdministratorsSid, [BackupFolderRules.SystemSid, BackupFolderRules.AdministratorsSid, BackupFolderRules.TrustedInstallerSid]);
            }
            return fake;
        }

        public bool Exists(string path) => Dirs.ContainsKey(path);
        public bool IsReparsePoint(string path) => Dirs[path].Reparse;
        public string OwnerSid(string path) => Failure is null ? Dirs[path].Owner! : throw Failure;
        public IReadOnlyList<string> WriteAccessSids(string path) => Dirs[path].Writers;
    }

    [Fact]
    public void FolderIsFixedUnderProgramFiles()
    {
        var paths = new HelperPaths { ProgramFiles = ProgramFiles };
        Assert.Equal(Folder, BackupFolderRules.FolderPath(paths));
    }

    [Fact]
    public void AcceptsAnAdminOnlyFolder()
    {
        Assert.Null(BackupFolderRules.Check(Folder, ProgramFiles, FakeInspector.Trusted()));
    }

    [Theory]
    [InlineData(@"C:\Program Files\Softwareverwaltung")]
    [InlineData(Folder)]
    public void AcceptsTheSystemAndTrustedInstallerAsOwner(string path)
    {
        var fake = FakeInspector.Trusted();
        fake.Dirs[path] = (false, BackupFolderRules.SystemSid, fake.Dirs[path].Writers);
        Assert.Null(BackupFolderRules.Check(Folder, ProgramFiles, fake));
        fake.Dirs[path] = (false, BackupFolderRules.TrustedInstallerSid, fake.Dirs[path].Writers);
        Assert.Null(BackupFolderRules.Check(Folder, ProgramFiles, fake));
    }

    [Theory]
    [InlineData(@"C:\Program Files\Softwareverwaltung")]
    [InlineData(Folder)]
    public void RefusesAMissingComponent(string missing)
    {
        var fake = FakeInspector.Trusted();
        fake.Dirs.Remove(missing);
        var problem = BackupFolderRules.Check(Folder, ProgramFiles, fake);
        Assert.Equal("BackupFolderMissing", problem!.Code);
        Assert.Equal(missing, problem.Args[0]);
    }

    [Theory]
    [InlineData(@"C:\Program Files\Softwareverwaltung")]
    [InlineData(Folder)]
    public void RefusesAReparsePointAnywhereOnTheWay(string path)
    {
        var fake = FakeInspector.Trusted();
        fake.Dirs[path] = (true, BackupFolderRules.AdministratorsSid, fake.Dirs[path].Writers);
        var problem = BackupFolderRules.Check(Folder, ProgramFiles, fake);
        Assert.Equal("BackupFolderReparsePoint", problem!.Code);
        Assert.Equal(path, problem.Args[0]);
    }

    [Theory]
    [InlineData(CurrentUser)]
    [InlineData(Users)]
    [InlineData(Everyone)]
    [InlineData(null)]
    public void RefusesAnOwnerWhoIsNotTrusted(string? owner)
    {
        var fake = FakeInspector.Trusted();
        fake.Dirs[Folder] = (false, owner, fake.Dirs[Folder].Writers);
        var problem = BackupFolderRules.Check(Folder, ProgramFiles, fake);
        Assert.Equal("BackupFolderBadOwner", problem!.Code);
        Assert.Equal(Folder, problem.Args[0]);
    }

    [Theory]
    [InlineData(Users)]
    [InlineData(AuthenticatedUsers)]
    [InlineData(Everyone)]
    [InlineData(CurrentUser)]
    [InlineData("S-1-3-0")]
    public void RefusesWriteAccessForAnyoneButAdministrators(string sid)
    {
        var fake = FakeInspector.Trusted();
        fake.Dirs[@"C:\Program Files\Softwareverwaltung"] = (false, BackupFolderRules.AdministratorsSid, [BackupFolderRules.AdministratorsSid, sid]);
        var problem = BackupFolderRules.Check(Folder, ProgramFiles, fake);
        Assert.Equal("BackupFolderWritable", problem!.Code);
        Assert.Equal(sid, problem.Args[1]);
    }

    [Fact]
    public void RefusesAnAceTheCheckCannotEvaluate()
    {
        var fake = FakeInspector.Trusted();
        fake.Dirs[Folder] = (false, BackupFolderRules.AdministratorsSid, [BackupFolderRules.AdministratorsSid, AclRules.UnsupportedAce]);
        var problem = BackupFolderRules.Check(Folder, ProgramFiles, fake);
        Assert.Equal("BackupFolderWritable", problem!.Code);
        Assert.Equal(AclRules.UnsupportedAce, problem.Args[1]);
    }

    [Theory]
    [InlineData(typeof(UnauthorizedAccessException))]
    [InlineData(typeof(IOException))]
    [InlineData(typeof(InvalidOperationException))]
    [InlineData(typeof(System.Security.SecurityException))]
    public void RefusesWhenTheRightsCannotBeRead(Type exception)
    {
        var fake = FakeInspector.Trusted();
        fake.Failure = (Exception)Activator.CreateInstance(exception)!;
        var problem = BackupFolderRules.Check(Folder, ProgramFiles, fake);
        Assert.Equal("BackupFolderUnreadable", problem!.Code);
        Assert.Equal(@"C:\Program Files\Softwareverwaltung", problem.Args[0]);
    }

    [Fact]
    public void RefusesFoldersOutsideProgramFiles()
    {
        var fake = FakeInspector.Trusted();
        foreach (var path in new[]
        {
            @"C:\ProgramData\Softwareverwaltung\RegistryBackup",
            @"C:\Program Files (x86)\Softwareverwaltung\RegistryBackup",
            @"C:\Program Files\..\ProgramData\Softwareverwaltung\RegistryBackup",
            @"C:\Program Files",
            "",
        })
        {
            Assert.Equal("BackupFolderOutsideRoot", BackupFolderRules.Check(path, ProgramFiles, fake)!.Code);
        }
    }

    [Fact]
    public void DetectsAJunctionWithTheRealInspector()
    {
        var root = Path.Combine(Path.GetTempPath(), "bfr-" + Guid.NewGuid().ToString("N"));
        var target = Path.Combine(root, "target");
        var link = Path.Combine(root, "link");
        Directory.CreateDirectory(target);
        try
        {
            using (var cmd = Process.Start(new ProcessStartInfo("cmd.exe", $"/c mklink /J \"{link}\" \"{target}\"") { CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true })!)
            {
                cmd.StandardOutput.ReadToEnd();
                cmd.WaitForExit();
            }
            var inspector = new WindowsDirectoryInspector();
            Assert.True(inspector.Exists(link));
            Assert.True(inspector.IsReparsePoint(link));
            Assert.False(inspector.IsReparsePoint(target));
            Assert.NotNull(inspector.OwnerSid(target));
            Assert.NotEmpty(inspector.WriteAccessSids(target));

            var problem = BackupFolderRules.Check(Path.Combine(link, "RegistryBackup"), root, inspector);
            Assert.Equal("BackupFolderReparsePoint", problem!.Code);
        }
        finally
        {
            if (Directory.Exists(link))
            {
                Directory.Delete(link);
            }
            Directory.Delete(root, true);
        }
    }
}
