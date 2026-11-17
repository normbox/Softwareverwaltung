using System.Security.AccessControl;
using SoftwareInventory.Helper;

namespace Softwareverwaltung.App.Tests;

/// <summary>
/// Die Rechte, mit denen der Helfer den Sicherungsordner und die Sicherungsdateien anlegt (SDDL in BackupFolderRules). Ein
/// Tippfehler darin bliebe sonst unbemerkt, weil das Anlegen nur erhöht unter Program Files geschieht.
/// </summary>
public sealed class BackupSecurityTests
{
    private const uint ReadAndExecute = 0x1200a9;

    private static RawSecurityDescriptor Parse(string sddl) => new(sddl);

    private static List<CommonAce> Aces(RawSecurityDescriptor descriptor) =>
        descriptor.DiscretionaryAcl!.Cast<GenericAce>().Select(a => (CommonAce)a).ToList();

    [Fact]
    public void TheFolderBelongsToAdministratorsIsProtectedAndOnlyAdministratorsMayWrite()
    {
        var folder = Parse(BackupFolderRules.FolderSddl);
        Assert.Equal(BackupFolderRules.AdministratorsSid, folder.Owner!.Value);
        Assert.True((folder.ControlFlags & ControlFlags.DiscretionaryAclProtected) != 0);
        Assert.All(WindowsDirectoryInspector.WriteSidsFromDescriptor(folder), sid => Assert.Contains(sid, BackupFolderRules.TrustedSids));
        // Dieselben Einträge gelten für Unterordner und Dateien (OI und CI).
        Assert.All(Aces(folder), ace => Assert.Equal(AceFlags.ObjectInherit | AceFlags.ContainerInherit, ace.AceFlags & AceFlags.InheritanceFlags));
    }

    [Fact]
    public void UsersAndTheOwnerOfNewFilesMayOnlyReadInTheFolder()
    {
        var aces = Aces(Parse(BackupFolderRules.FolderSddl));
        var users = Assert.Single(aces, a => a.SecurityIdentifier.Value == "S-1-5-32-545");
        Assert.Equal(ReadAndExecute, unchecked((uint)users.AccessMask));
        var owner = Assert.Single(aces, a => a.SecurityIdentifier.Value == BackupFolderRules.OwnerRightsSid);
        Assert.Equal(ReadAndExecute, unchecked((uint)owner.AccessMask));
        Assert.False(AclRules.IsWriteMask(ReadAndExecute));
        Assert.True(BackupFolderRules.LimitsOwnerRightsOfNewFiles(Parse(BackupFolderRules.FolderSddl)));
    }

    [Fact]
    public void AFolderWithoutAnInheritedOwnerRightsEntryIsNotEnough()
    {
        Assert.False(BackupFolderRules.LimitsOwnerRightsOfNewFiles(Parse("O:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)")));
        // Nur für den Ordner selbst (ohne OI) erben neue Dateien den Eintrag nicht.
        Assert.False(BackupFolderRules.LimitsOwnerRightsOfNewFiles(Parse("O:BAD:P(A;CI;FA;;;BA)(A;CI;0x1200a9;;;OW)")));
        Assert.False(BackupFolderRules.LimitsOwnerRightsOfNewFiles(Parse("O:BAD:P(D;OICI;FA;;;OW)(A;OICI;FA;;;BA)")));
        Assert.False(BackupFolderRules.LimitsOwnerRightsOfNewFiles(Parse("O:BA")));
        Assert.True(BackupFolderRules.LimitsOwnerRightsOfNewFiles(Parse("O:BAD:(A;OI;0x1200a9;;;OW)")));
    }

    [Fact]
    public void FilesWrittenByTheHelperPassTheFileCheck()
    {
        var file = Parse(BackupFolderRules.FileSddl);
        Assert.Equal(BackupFolderRules.AdministratorsSid, file.Owner!.Value);
        Assert.True((file.ControlFlags & ControlFlags.DiscretionaryAclProtected) != 0);
        var info = new BackupFileInfo { LinkCount = 1, OwnerSid = file.Owner!.Value, WriteAccessSids = WindowsDirectoryInspector.WriteSidsFromDescriptor(file) };
        Assert.Null(BackupFileRules.CheckFile(@"C:\x.reg", info));
        var users = Assert.Single(Aces(file), a => a.SecurityIdentifier.Value == "S-1-5-32-545");
        Assert.Equal(ReadAndExecute, unchecked((uint)users.AccessMask));
    }

    [Fact]
    public void TheParentGetsOnlyAnOwnerAndInheritsItsRightsFromProgramFiles()
    {
        var parent = Parse(BackupFolderRules.ParentSddl);
        Assert.Equal(BackupFolderRules.AdministratorsSid, parent.Owner!.Value);
        Assert.Null(parent.DiscretionaryAcl);
        Assert.True((parent.ControlFlags & ControlFlags.DiscretionaryAclPresent) == 0);
    }
}
