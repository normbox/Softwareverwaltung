using System.Text;
using SoftwareInventory.Helper;

namespace Softwareverwaltung.App.Tests;

/// <summary>
/// Nur unter .NET Framework (JavaScriptSerializer wie im Helfer): Die Begleitdatei, die der Helfer selbst schreibt
/// (RegistryRemoval.BuildSidecar, mit Escape-Folgen), und die des Moduls (ConvertTo-Json) werden richtig gelesen.
/// </summary>
public sealed class SidecarParserTests
{
    private const string Id = "0f8fad5b-d9cb-469f-a165-70867728950e";
    private const string Key = @"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\App";

    [Fact]
    public void ReadsTheSidecarTheHelperWrites()
    {
        var name = "Ä \"B\" \\ C" + (char)0x2028;
        var bytes = RegistryRemoval.BuildSidecar(Id, name, Key, DateTime.UtcNow, new[] { new BackupReason("NewerInstallNextTo", new object[] { "x" }) });
        var sidecar = SidecarParser.Parse(bytes);
        Assert.NotNull(sidecar);
        Assert.Equal(1, sidecar!.SchemaVersion);
        Assert.Equal(Id, sidecar.ActionId);
        Assert.Equal(Key, sidecar.NativeKey);
        Assert.Equal("Machine", sidecar.Scope);
    }

    [Fact]
    public void ReadsTheModuleFormatToo()
    {
        var json = "{\r\n  \"SchemaVersion\": 1,\r\n  \"ActionId\": \"" + Id + "\",\r\n  \"CreatedAt\": \"2026-11-17T12:00:00.0000000Z\",\r\n  \"Name\": \"App\",\r\n  \"NativeKey\": \"" + Key.Replace(@"\", @"\\") + "\",\r\n  \"Scope\": \"Machine\",\r\n  \"Reasons\": []\r\n}";
        var sidecar = SidecarParser.Parse(Encoding.UTF8.GetBytes(json));
        Assert.Equal(Key, sidecar!.NativeKey);
        Assert.Equal(1, sidecar.SchemaVersion);
    }

    [Theory]
    [InlineData("")]
    [InlineData("kein json")]
    [InlineData("[1, 2]")]
    [InlineData("\"text\"")]
    [InlineData("{\"SchemaVersion\": \"1\"}")]
    public void UnusableBytesGiveNothingOrNoSchemaVersion(string json)
    {
        var sidecar = SidecarParser.Parse(Encoding.UTF8.GetBytes(json));
        Assert.True(sidecar is null || sidecar.SchemaVersion == 0);
    }

    [Fact]
    public void InvalidUtf8AndTooLargeFilesAreRefused()
    {
        Assert.Null(SidecarParser.Parse(new byte[] { 0x7B, 0xC3, 0x28, 0x7D }));
        Assert.Null(SidecarParser.Parse(new byte[SidecarParser.MaxBytes + 1]));
        Assert.Null(SidecarParser.Parse(null!));
    }
}
