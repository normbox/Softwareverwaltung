using System.Diagnostics;
using System.Security.Principal;
using SoftwareInventory.Helper;

namespace Softwareverwaltung.App.Tests;

/// <summary>
/// Einzelprüfung einer Sicherungsdatei im Admin-Ordner: kein Link, genau ein Hardlink, vertrauenswürdiger Besitzer,
/// kein Schreibrecht für andere. Die Regeln laufen gegen angegebene Werte; der Leser (ein Handle, ohne einem Link zu
/// folgen) wird mit echten Dateien im Temp-Ordner geprüft.
/// </summary>
public sealed class BackupFileRulesTests
{
    private const string File1 = @"C:\Program Files\Softwareverwaltung\RegistryBackup\a.reg";
    private const string Users = "S-1-5-32-545";
    private const string CurrentUser = "S-1-5-21-1-2-3-1001";

    private static BackupFileInfo Trusted() => new()
    {
        IsReparsePoint = false,
        LinkCount = 1,
        OwnerSid = BackupFolderRules.AdministratorsSid,
        WriteAccessSids = [BackupFolderRules.SystemSid, BackupFolderRules.AdministratorsSid, BackupFolderRules.TrustedInstallerSid],
    };

    [Fact]
    public void AcceptsAFileOwnedByAdministratorsThatOnlyTheyCanWrite()
    {
        Assert.Null(BackupFileRules.CheckFile(File1, Trusted()));
    }

    [Fact]
    public void RefusesALinkBeforeLookingAtAnythingElse()
    {
        var info = Trusted();
        info.IsReparsePoint = true;
        info.LinkCount = 5;
        info.OwnerSid = CurrentUser;
        var problem = BackupFileRules.CheckFile(File1, info);
        Assert.Equal("BackupFileReparsePoint", problem!.Code);
        Assert.Equal(File1, problem.Args[0]);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(2)]
    [InlineData(7)]
    public void RefusesAnyLinkCountButOne(int links)
    {
        var info = Trusted();
        info.LinkCount = links;
        var problem = BackupFileRules.CheckFile(File1, info);
        Assert.Equal("BackupFileHardLinked", problem!.Code);
        Assert.Equal(links, problem.Args[1]);
    }

    [Theory]
    [InlineData(CurrentUser)]
    [InlineData(Users)]
    [InlineData("")]
    [InlineData(null)]
    public void RefusesAnOwnerWhoIsNotTrusted(string? owner)
    {
        var info = Trusted();
        info.OwnerSid = owner!;
        Assert.Equal("BackupFileBadOwner", BackupFileRules.CheckFile(File1, info)!.Code);
    }

    [Theory]
    [InlineData(Users)]
    [InlineData(CurrentUser)]
    [InlineData("S-1-1-0")]
    [InlineData("S-1-3-4")]
    public void RefusesWriteAccessForAnyoneButAdministrators(string sid)
    {
        var info = Trusted();
        info.WriteAccessSids = [BackupFolderRules.AdministratorsSid, sid];
        var problem = BackupFileRules.CheckFile(File1, info);
        Assert.Equal("BackupFileWritable", problem!.Code);
        Assert.Equal(sid, problem.Args[1]);
    }

    [Fact]
    public void RefusesAnAceItCannotEvaluate()
    {
        var info = Trusted();
        info.WriteAccessSids = [AclRules.UnsupportedAce];
        Assert.Equal("BackupFileWritable", BackupFileRules.CheckFile(File1, info)!.Code);
    }

    private static string NewTempFolder()
    {
        var folder = Path.Combine(Path.GetTempPath(), "bfr-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        return folder;
    }

    private static void RunCmd(string arguments)
    {
        var cmd = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        using var process = Process.Start(new ProcessStartInfo(cmd, "/c " + arguments) { CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true })!;
        process.StandardOutput.ReadToEnd();
        process.StandardError.ReadToEnd();
        process.WaitForExit();
    }

    [Fact]
    public void TheReaderReturnsTheBytesAndTheFileDetailsFromOneHandle()
    {
        var folder = NewTempFolder();
        try
        {
            var file = Path.Combine(folder, "a.reg");
            var bytes = new byte[] { 0xFF, 0xFE, 0x41, 0x00 };
            File.WriteAllBytes(file, bytes);
            var read = new WindowsBackupFileReader().Read(file);
            Assert.Equal(bytes, read.Bytes);
            Assert.Equal(4, read.Size);
            Assert.False(read.Info.IsReparsePoint);
            Assert.Equal(1, read.Info.LinkCount);
            Assert.False(string.IsNullOrEmpty(read.Info.OwnerSid));
            Assert.NotEmpty(read.Info.WriteAccessSids);
            // Der Besitzer ist hier der Benutzer (oder die Administratoren-Gruppe): Die Prüfung entscheidet darüber, nicht der Leser.
            Assert.IsType<SecurityIdentifier>(new SecurityIdentifier(read.Info.OwnerSid));
        }
        finally
        {
            Directory.Delete(folder, true);
        }
    }

    [Fact]
    public void TheReaderCountsHardLinks()
    {
        var folder = NewTempFolder();
        try
        {
            var file = Path.Combine(folder, "a.reg");
            var link = Path.Combine(folder, "b.reg");
            File.WriteAllBytes(file, [0xFF, 0xFE]);
            RunCmd($"mklink /H \"{link}\" \"{file}\"");
            var read = new WindowsBackupFileReader().Read(file);
            Assert.Equal(2, read.Info.LinkCount);
            // Die Hardlink-Prüfung kommt vor Besitzer und Rechten: Der Fund steht fest, wer auch immer die Datei besitzt.
            Assert.Equal("BackupFileHardLinked", BackupFileRules.CheckFile(file, read.Info)!.Code);
        }
        finally
        {
            Directory.Delete(folder, true);
        }
    }

    [Fact]
    public void TheReaderDoesNotFollowASymbolicLink()
    {
        var folder = NewTempFolder();
        try
        {
            var target = Path.Combine(folder, "target.reg");
            var link = Path.Combine(folder, "link.reg");
            File.WriteAllBytes(target, [0xFF, 0xFE, 0x41, 0x00]);
            try
            {
                File.CreateSymbolicLink(link, target);
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException or IOException)
            {
                // Ohne Recht zum Anlegen von Symlinks (Entwicklermodus aus) lässt sich dieser Fall nicht nachstellen.
                return;
            }
            var read = new WindowsBackupFileReader().Read(link);
            Assert.True(read.Info.IsReparsePoint);
            Assert.Null(read.Bytes);
            Assert.Equal("BackupFileReparsePoint", BackupFileRules.CheckFile(link, read.Info)!.Code);
        }
        finally
        {
            Directory.Delete(folder, true);
        }
    }

    [Fact]
    public void TheReaderLeavesTooLargeFilesUnread()
    {
        var folder = NewTempFolder();
        try
        {
            var file = Path.Combine(folder, "big.reg");
            using (var stream = File.Create(file))
            {
                stream.SetLength(BackupFileRules.MaxBytes + 1);
            }
            var read = new WindowsBackupFileReader().Read(file);
            Assert.Equal(BackupFileRules.MaxBytes + 1, read.Size);
            Assert.Null(read.Bytes);
        }
        finally
        {
            Directory.Delete(folder, true);
        }
    }

    [Fact]
    public void TheReaderThrowsForAMissingFile()
    {
        var file = Path.Combine(Path.GetTempPath(), "gibt-es-nicht-" + Guid.NewGuid().ToString("N") + ".reg");
        Assert.Throws<FileNotFoundException>(() => new WindowsBackupFileReader().Read(file));
    }

    [Fact]
    public void TheReaderHoldsTheFileOpenForReadingOnlyWhileItReads()
    {
        var folder = NewTempFolder();
        try
        {
            var file = Path.Combine(folder, "a.reg");
            File.WriteAllBytes(file, [0xFF, 0xFE]);
            new WindowsBackupFileReader().Read(file);
            // Nach dem Lesen ist das Handle zu: Die Datei lässt sich löschen (sonst bliebe sie gesperrt).
            File.Delete(file);
            Assert.False(File.Exists(file));
        }
        finally
        {
            Directory.Delete(folder, true);
        }
    }
}
