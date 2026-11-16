using System.Security.AccessControl;
using System.Security.Principal;
using SoftwareInventory.Helper;

namespace Softwareverwaltung.App.Tests;

/// <summary>Welche Zugriffsrechte und Einträge der Zugriffssteuerungsliste als „Schreiben“ zählen (Ordner für HKLM-Sicherungen).</summary>
public sealed class AclRulesTests
{
    private const string Users = "S-1-5-32-545";
    private const string AuthenticatedUsers = "S-1-5-11";
    private const string Everyone = "S-1-1-0";

    [Theory]
    [InlineData(0x2u)]        // FILE_WRITE_DATA / ADD_FILE
    [InlineData(0x4u)]        // FILE_APPEND_DATA / ADD_SUBDIRECTORY
    [InlineData(0x10u)]       // FILE_WRITE_EA
    [InlineData(0x40u)]       // FILE_DELETE_CHILD
    [InlineData(0x100u)]      // FILE_WRITE_ATTRIBUTES
    [InlineData(0x10000u)]    // DELETE
    [InlineData(0x40000u)]    // WRITE_DAC
    [InlineData(0x80000u)]    // WRITE_OWNER
    [InlineData(0x10000000u)] // GENERIC_ALL (nicht gemappt)
    [InlineData(0x40000000u)] // GENERIC_WRITE (nicht gemappt)
    [InlineData(0x02000000u)] // MAXIMUM_ALLOWED
    [InlineData(0x1F01FFu)]   // FILE_ALL_ACCESS
    [InlineData(0x120116u)]   // FILE_GENERIC_WRITE
    public void CountsWriteRights(uint mask) => Assert.True(AclRules.IsWriteMask(mask));

    [Theory]
    [InlineData(0x1u)]        // FILE_READ_DATA
    [InlineData(0x8u)]        // FILE_READ_EA
    [InlineData(0x20u)]       // FILE_EXECUTE
    [InlineData(0x80u)]       // FILE_READ_ATTRIBUTES
    [InlineData(0x20000u)]    // READ_CONTROL
    [InlineData(0x100000u)]   // SYNCHRONIZE
    [InlineData(0x80000000u)] // GENERIC_READ
    [InlineData(0x20000000u)] // GENERIC_EXECUTE
    [InlineData(0x120089u)]   // FILE_GENERIC_READ
    [InlineData(0x1200A9u)]   // FILE_GENERIC_READ | FILE_EXECUTE
    public void DoesNotCountReadRights(uint mask) => Assert.False(AclRules.IsWriteMask(mask));

    [Theory]
    [InlineData("D:(A;;GA;;;WD)", Everyone)]
    [InlineData("D:(A;;0x40000000;;;BU)", Users)]
    [InlineData("D:(A;;GW;;;BU)", Users)]
    [InlineData("D:(A;;0x2;;;AU)", AuthenticatedUsers)]
    [InlineData("D:(A;OICIIO;GW;;;BU)", Users)]
    [InlineData("D:(A;OICI;GA;;;AU)", AuthenticatedUsers)]
    [InlineData("D:(A;;GA;;;CO)", "S-1-3-0")]
    [InlineData("D:(D;;GR;;;BU)(A;;GA;;;BU)", Users)]
    public void FindsWriteAccess(string sddl, string sid)
    {
        Assert.Contains(sid, WindowsDirectoryInspector.WriteSidsFromDescriptor(new RawSecurityDescriptor(sddl)));
    }

    [Theory]
    [InlineData("D:(A;;FR;;;BU)")]
    [InlineData("D:(A;;GR;;;WD)")]
    [InlineData("D:(A;OICIIO;GA;;;CO)")]      // Platzhalter, wird beim Erben zum Ersteller
    [InlineData("D:(A;OICIIO;GA;;;CG)")]
    [InlineData("D:(A;IO;GW;;;BU)")]          // nur vererbt, aber an niemanden
    [InlineData("D:(D;;GA;;;BU)(A;;GR;;;BU)")]
    public void IgnoresEntriesWithoutWriteAccess(string sddl)
    {
        Assert.Empty(WindowsDirectoryInspector.WriteSidsFromDescriptor(new RawSecurityDescriptor(sddl)));
    }

    [Fact]
    public void ListsEveryAdministratorEntryToo()
    {
        var sids = WindowsDirectoryInspector.WriteSidsFromDescriptor(new RawSecurityDescriptor("D:(A;;GA;;;BA)(A;;GA;;;SY)"));
        Assert.Equal([BackupFolderRules.AdministratorsSid, BackupFolderRules.SystemSid], sids);
    }

    [Fact]
    public void ANullDaclMeansEveryoneMayWrite()
    {
        var descriptor = new RawSecurityDescriptor(ControlFlags.None, null, null, null, null);
        Assert.Equal([Everyone], WindowsDirectoryInspector.WriteSidsFromDescriptor(descriptor));
    }

    [Fact]
    public void AnAllowEntryItCannotEvaluateCountsAsWriteAccess()
    {
        var acl = new RawAcl(GenericAcl.AclRevisionDS, 1);
        acl.InsertAce(0, new ObjectAce(AceFlags.None, AceQualifier.AccessAllowed, 0x2, new SecurityIdentifier(Users), ObjectAceFlags.None, Guid.Empty, Guid.Empty, false, null));
        var descriptor = new RawSecurityDescriptor(ControlFlags.DiscretionaryAclPresent, null, null, null, acl);
        Assert.Equal([AclRules.UnsupportedAce], WindowsDirectoryInspector.WriteSidsFromDescriptor(descriptor));
    }
}
