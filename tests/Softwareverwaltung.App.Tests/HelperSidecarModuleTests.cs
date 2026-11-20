using System.Management.Automation;
using System.Text;
using Softwareverwaltung.App.Services;
using SoftwareInventory.Helper;

namespace Softwareverwaltung.App.Tests;

/// <summary>
/// Gegenprobe zur strengen Prüfung der Begleitdatei im Modul (Read-RegistryBackupSidecar -Strict): Eine Sicherung mit genau
/// den Bytes, die der Helfer schreibt (RegistryRemoval.BuildSidecar, CRLF, Escape-Folgen), muss das Modul als gültig ansehen.
/// Sonst wäre das Modul strenger als der Helfer und zeigte eine echte HKLM-Sicherung fälschlich als ungültig.
/// Der Admin-Ordner ist auf ein Testverzeichnis umgelenkt; HKLM wird nur gelesen (der Schlüssel existiert nicht).
/// </summary>
public sealed class HelperSidecarModuleTests : IAsyncLifetime
{
    private const string Key = @"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SoftwareverwaltungSidecarProbe";
    private readonly PowerShellHost _host = new();
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "SoftwareverwaltungTests", Guid.NewGuid().ToString("N"));

    private string MachineFolder => Path.Combine(_directory, "machine-backup");

    public async Task InitializeAsync()
    {
        await _host.InitializeAsync();
        Directory.CreateDirectory(MachineFolder);
        var result = await _host.InvokeAsync(new PSCommand().AddScript("""
            param($Dir, $Machine)
            & (Get-Module SoftwareInventory) {
                param($Dir, $Machine)
                $script:TestAppData = $Dir
                $script:TestMachine = $Machine
                function script:Get-AppDataDirectory { $script:TestAppData }
                function script:Get-SettingsPath { Join-Path $script:TestAppData 'settings.json' }
                function script:Get-RegistryBackupMachineDirectory { $script:TestMachine }
            } $Dir $Machine
            """).AddParameter("Dir", _directory).AddParameter("Machine", MachineFolder));
        Assert.Empty(result.Errors);
    }

    public Task DisposeAsync()
    {
        _host.Dispose();
        Directory.Delete(_directory, recursive: true);
        return Task.CompletedTask;
    }

    [Theory]
    [InlineData("Alt-Programm")]
    [InlineData("Alt \"Programm\" \\ äöü")]
    [InlineData("Zeilentrenner")]
    public async Task TheModuleAcceptsTheSidecarBytesTheHelperWrites(string name)
    {
        if (name == "Zeilentrenner")
        {
            // Wird vom Helfer als Escape-Folge geschrieben; im Testcode als Zeichen aus dem Codepunkt.
            name = "A" + (char)0x2028 + "B" + (char)0x01;
        }
        var id = Guid.NewGuid().ToString();
        var reg = Encoding.Unicode.GetPreamble()
            .Concat(Encoding.Unicode.GetBytes($"Windows Registry Editor Version 5.00\r\n\r\n[{Key}]\r\n\"DisplayName\"=\"x\"\r\n"))
            .ToArray();
        File.WriteAllBytes(Path.Combine(MachineFolder, id + ".reg"), reg);
        var sidecar = RegistryRemoval.BuildSidecar(id, name, Key, DateTime.UtcNow, [new BackupReason("NewerInstallNextTo", ["Neu", "2.0"])]);
        File.WriteAllBytes(Path.Combine(MachineFolder, id + ".json"), sidecar);

        var result = await _host.InvokeAsync(new PSCommand().AddCommand("Get-RegistryBackup").AddParameter("Id", id));

        Assert.Empty(result.Errors);
        var backup = Assert.Single(result.Output);
        Assert.Null(backup.Properties["Problem"]?.Value);
        Assert.Equal(true, backup.Properties["CanRestore"]?.Value);
        Assert.Equal("Machine", backup.Properties["Scope"]?.Value);
        Assert.Equal(name, backup.Properties["Name"]?.Value);
        Assert.Equal(Key, backup.Properties["NativeKey"]?.Value);
    }
}
