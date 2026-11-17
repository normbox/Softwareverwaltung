using System.Text;
using System.Text.Json;
using SoftwareInventory.Helper;

namespace Softwareverwaltung.App.Tests;

/// <summary>
/// Entfernen eines verwaisten HKLM-Eintrags durch den Helfer (Operation RemoveRegistryEntry), mit nachgebildetem System:
/// Der Helfer prüft alles selbst, sichert über eine Zwischendatei, schreibt die endgültige Sicherung selbst und löscht den
/// Schlüssel erst danach. Scheitert etwas, bleibt der Schlüssel und keine unvollständige Sicherung liegen.
/// </summary>
public sealed class RegistryRemovalTests
{
    private const string Id = "0f8fad5b-d9cb-469f-a165-70867728950e";
    private const string Folder = @"C:\Program Files\Softwareverwaltung\RegistryBackup";
    private const string Machine = @"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall";
    private const string Machine32 = @"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall";
    private const string PlanKey = @"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OldApp";
    private const string Admins = "S-1-5-32-544";

    /// <summary>Alles, was der Ablauf vom System braucht, im Speicher.</summary>
    private sealed class FakeSystem : IRegistryRemovalSystem
    {
        public bool Elevated { get; set; } = true;
        public IOrphanEnvironment Environment { get; } = new FakeOrphanEnvironment();
        public string BackupFolder => Folder;
        public DateTime UtcNow => new(2026, 11, 17, 12, 0, 0, DateTimeKind.Utc);

        public Dictionary<string, UninstallEntry> Keys { get; } = new(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, byte[]> Files { get; } = new(StringComparer.OrdinalIgnoreCase);
        public HashSet<string> CreatedFiles { get; } = new(StringComparer.OrdinalIgnoreCase);
        public List<string> Calls { get; } = new();

        public Problem? FolderCreate { get; set; }
        public Problem? FolderCheck { get; set; }
        public int ExportExit { get; set; }
        public Func<string, byte[]>? ExportBytes { get; set; }
        public Func<string, BackupFileInfo>? FileInfoFor { get; set; }
        public Func<string, byte[], byte[]>? AfterWrite { get; set; }
        public bool ReadEntryThrows { get; set; }
        public bool DeleteKeyThrows { get; set; }
        public bool KeyStaysAfterDelete { get; set; }
        public bool SidecarWriteFails { get; set; }
        public bool ReadingTheFinalFileThrowsUnexpectedly { get; set; }

        public UninstallEntry ReadEntry(string nativeKey)
        {
            Calls.Add("ReadEntry");
            if (ReadEntryThrows)
            {
                throw new UnauthorizedAccessException();
            }
            return Keys.TryGetValue(nativeKey, out var entry) ? entry : null!;
        }

        public Problem CreateBackupFolderIfMissing()
        {
            Calls.Add("CreateFolder");
            return FolderCreate!;
        }

        public Problem CheckBackupFolder()
        {
            Calls.Add("CheckFolder");
            return FolderCheck!;
        }

        public int ExportKey(string nativeKey, string file)
        {
            Calls.Add("Export " + Path.GetFileName(file));
            if (ExportExit == 0)
            {
                Files[file] = (ExportBytes ?? (k => Reg(k)))(nativeKey);
            }
            return ExportExit;
        }

        public BackupFileRead ReadFile(string path)
        {
            Calls.Add("Read " + Path.GetFileName(path));
            if (ReadingTheFinalFileThrowsUnexpectedly && path.EndsWith(".reg", StringComparison.Ordinal))
            {
                throw new NotSupportedException();
            }
            if (!Files.TryGetValue(path, out var bytes))
            {
                throw new FileNotFoundException();
            }
            var info = FileInfoFor?.Invoke(path) ?? new BackupFileInfo { LinkCount = 1, OwnerSid = Admins, WriteAccessSids = new[] { Admins } };
            return new BackupFileRead { Info = info, Size = bytes.Length, Bytes = bytes };
        }

        public void WriteNewFile(string path, byte[] bytes)
        {
            Calls.Add("Write " + Path.GetFileName(path));
            if (Files.ContainsKey(path) || (SidecarWriteFails && path.EndsWith(".json", StringComparison.Ordinal)))
            {
                throw new IOException("exists");
            }
            Files[path] = AfterWrite?.Invoke(path, bytes) ?? bytes;
            CreatedFiles.Add(path);
        }

        public void DeleteFile(string path)
        {
            Calls.Add("Delete " + Path.GetFileName(path));
            Files.Remove(path);
        }

        public void DeleteKey(string nativeKey)
        {
            Calls.Add("DeleteKey");
            if (DeleteKeyThrows)
            {
                throw new UnauthorizedAccessException();
            }
            if (!KeyStaysAfterDelete)
            {
                Keys.Remove(nativeKey);
            }
        }

        public bool KeyExists(string nativeKey) => Keys.ContainsKey(nativeKey);
    }

    /// <summary>Alle Pfade unter C:\ fehlen; nur C:\ ist ein festes Laufwerk.</summary>
    private sealed class FakeOrphanEnvironment : IOrphanEnvironment
    {
        public HashSet<string> Existing { get; } = new(StringComparer.OrdinalIgnoreCase);
        public string ExpandVariables(string text) => text;
        public PathState PathStatus(string path) => Existing.Contains(path) ? PathState.Exists : PathState.Missing;
        public string SystemDriveRoot => @"C:\";
        public IReadOnlyList<string> NativeProgramFolders => new[] { @"C:\Program Files" };
        public bool FileExists(string path) => Existing.Contains(path);
        public bool RootReachable(string root) => root == @"C:\";
        public string DriveType(string root) => "Fixed";
        public bool IsUserProfilePath(string path) => false;
        public IReadOnlyList<string> SystemFolders => new[] { @"C:\Windows\System32", @"C:\Windows" };
        public string SystemFolder => @"C:\Windows\System32";
    }

    private static byte[] Reg(string nativeKey, string body = "\"DisplayName\"=\"Old App\"\r\n")
    {
        var text = "Windows Registry Editor Version 5.00\r\n\r\n[" + nativeKey + "]\r\n" + body + "\r\n";
        return new byte[] { 0xFF, 0xFE }.Concat(Encoding.Unicode.GetBytes(text)).ToArray();
    }

    private static UninstallEntry Orphan(string folder = @"C:\Program Files\OldApp") => new()
    {
        DisplayName = "Old App",
        UninstallString = "\"" + folder + "\\unins000.exe\" /S",
        InstallLocation = folder,
    };

    private static FakeSystem SystemWithOrphan(string nativeKey = Machine + @"\OldApp")
    {
        var system = new FakeSystem();
        system.Keys[nativeKey] = Orphan();
        return system;
    }

    private static RegistryRemovalOutcome Run(FakeSystem system, string key = PlanKey, string id = Id, IEnumerable<BackupReason>? reasons = null) =>
        RegistryRemoval.Run(key, id, reasons ?? new[] { new BackupReason("OrphanedEntry", null!) }, system);

    [Fact]
    public void BacksUpThroughAStagedFileWritesItsOwnCopyAndOnlyThenDeletesTheKey()
    {
        var system = SystemWithOrphan();
        var outcome = Run(system);

        Assert.Null(outcome.Problem);
        Assert.True(outcome.Removed);
        Assert.Equal(Path.Combine(Folder, Id + ".reg"), outcome.BackupFile);
        Assert.Equal(Machine + @"\OldApp", outcome.NativeKey);
        Assert.Empty(system.Keys);
        Assert.Equal(
            new[] { "ReadEntry", "CreateFolder", "CheckFolder", "Export " + Id + ".tmp", "Read " + Id + ".tmp", "Write " + Id + ".reg", "Read " + Id + ".reg", "Write " + Id + ".json", "Delete " + Id + ".tmp", "DeleteKey" },
            system.Calls);
        Assert.Equal(new[] { Id + ".json", Id + ".reg" }, system.Files.Keys.Select(Path.GetFileName).OrderBy(n => n, StringComparer.Ordinal));
        Assert.Equal(Reg(Machine + @"\OldApp"), system.Files[Path.Combine(Folder, Id + ".reg")]);
    }

    [Fact]
    public void TheSidecarHasTheModuleFormatWithOnlyKnownReasons()
    {
        var system = SystemWithOrphan();
        var reasons = new[]
        {
            new BackupReason("NewerInstallNextTo", new object[] { "Old App 2.0", new string('x', 300), "c", "d", "e" }),
            new BackupReason("Erfunden", new object[] { "nein" }),
            new BackupReason("orphanedentry", null!),
        };
        Run(system, reasons: reasons);

        using var doc = JsonDocument.Parse(system.Files[Path.Combine(Folder, Id + ".json")]);
        var root = doc.RootElement;
        Assert.Equal(1, root.GetProperty("SchemaVersion").GetInt32());
        Assert.Equal(Id, root.GetProperty("ActionId").GetString());
        Assert.Equal("Old App", root.GetProperty("Name").GetString());
        Assert.Equal(Machine + @"\OldApp", root.GetProperty("NativeKey").GetString());
        Assert.Equal("Machine", root.GetProperty("Scope").GetString());
        Assert.Equal("2026-11-17T12:00:00.0000000Z", root.GetProperty("CreatedAt").GetString());
        var codes = root.GetProperty("Reasons").EnumerateArray().Select(r => r.GetProperty("Code").GetString()).ToList();
        Assert.Equal(new[] { "OrphanedEntry", "NewerInstallNextTo" }, codes);
        var args = root.GetProperty("Reasons")[1].GetProperty("Args").EnumerateArray().Select(a => a.GetString()!).ToList();
        Assert.Equal(4, args.Count);
        Assert.Equal(200, args[1].Length);
    }

    [Fact]
    public void TheSidecarEscapesQuotesControlCharactersAndLineSeparators()
    {
        var name = "A \"B\" \\ C" + (char)0x01 + (char)0x2028 + "ä";
        var bytes = RegistryRemoval.BuildSidecar(Id, name, Machine + @"\X", DateTime.UtcNow, null!);
        foreach (var b in bytes)
        {
            Assert.InRange(b, (byte)0x0A, (byte)0x7E);
        }
        using var doc = JsonDocument.Parse(bytes);
        Assert.Equal(name, doc.RootElement.GetProperty("Name").GetString());
        Assert.Equal("OrphanedEntry", doc.RootElement.GetProperty("Reasons")[0].GetProperty("Code").GetString());
    }

    [Fact]
    public void The32BitBranchIsCheckedAsX86AndExportedUnderWow6432Node()
    {
        var system = SystemWithOrphan(Machine32 + @"\OldApp");
        var outcome = Run(system, @"HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OldApp");
        // Unter dem 64-Bit-Programmordner lässt sich ein 32-Bit-Eintrag nicht beurteilen: nicht verwaist.
        Assert.Equal("RemoveEntryNotOrphaned", outcome.Problem!.Code);
        Assert.Equal(new object[] { "PathUnknown" }, outcome.Problem.Args);

        system.Keys[Machine32 + @"\OldApp"] = Orphan(@"C:\Program Files (x86)\OldApp");
        outcome = Run(system, @"HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OldApp");
        Assert.True(outcome.Removed);
        Assert.Equal(Machine32 + @"\OldApp", outcome.NativeKey);
    }

    [Theory]
    [InlineData(@"HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OldApp")]
    [InlineData(@"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")]
    [InlineData(@"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OldApp\Sub")]
    [InlineData(@"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\OldApp")]
    [InlineData(@"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\..\Run")]
    [InlineData(@"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OldApp")]
    [InlineData("")]
    public void OnlyKeysDirectlyUnderAMachineUninstallBranch(string key)
    {
        var system = SystemWithOrphan();
        Assert.Equal("RemoveEntryNotUninstallKey", Run(system, key).Problem!.Code);
        Assert.Empty(system.Calls);
    }

    [Theory]
    [InlineData("Old\"App")]
    [InlineData("Old[App")]
    [InlineData("Old]App")]
    public void UnsafeKeyNamesAreRefusedBeforeAnythingIsRead(string name)
    {
        var system = SystemWithOrphan();
        Assert.Equal("BackupKeyNameUnsafe", Run(system, @"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\" + name).Problem!.Code);
        Assert.Empty(system.Calls);
    }

    [Fact]
    public void UnsafeKeyNamesWithAControlCharacterAreRefused()
    {
        var system = SystemWithOrphan();
        Assert.Equal("BackupKeyNameUnsafe", Run(system, PlanKey + (char)0x09 + "x").Problem!.Code);
    }

    [Theory]
    [InlineData("")]
    [InlineData("kein-guid")]
    [InlineData("0f8fad5b-d9cb-469f-a165-70867728950e\\..\\x")]
    [InlineData("0f8fad5b-d9cb-469f-a165-70867728950")]
    public void TheActionIdMustBeAGuid(string id)
    {
        var system = SystemWithOrphan();
        Assert.Equal("RemoveEntryBadActionId", Run(system, id: id).Problem!.Code);
        Assert.Empty(system.Calls);
    }

    [Fact]
    public void RefusesWithoutAdministratorRights()
    {
        var system = SystemWithOrphan();
        system.Elevated = false;
        Assert.Equal("RemoveEntryNotElevated", Run(system).Problem!.Code);
        Assert.Empty(system.Calls);
    }

    [Fact]
    public void AGoneOrUnreadableKeyIsNotTouched()
    {
        var system = new FakeSystem();
        Assert.Equal("RemoveEntryKeyGone", Run(system).Problem!.Code);
        system = SystemWithOrphan();
        system.ReadEntryThrows = true;
        Assert.Equal("RemoveEntryKeyUnreadable", Run(system).Problem!.Code);
        Assert.Equal(new[] { "ReadEntry" }, system.Calls);
    }

    [Fact]
    public void AnEntryThatIsNoLongerOrphanedOrIsMsiIsRefusedWithTheReason()
    {
        var system = SystemWithOrphan();
        ((FakeOrphanEnvironment)system.Environment).Existing.Add(@"C:\Program Files\OldApp\unins000.exe");
        var outcome = Run(system);
        Assert.Equal("RemoveEntryNotOrphaned", outcome.Problem!.Code);
        Assert.Equal(new object[] { "PathExists" }, outcome.Problem.Args);

        system = SystemWithOrphan();
        system.Keys[Machine + @"\OldApp"].IsMsi = true;
        Assert.Equal(new object[] { "Msi" }, Run(system).Problem!.Args);
        Assert.Single(system.Keys);
        Assert.DoesNotContain("CreateFolder", system.Calls);
    }

    [Fact]
    public void AFolderProblemStopsBeforeTheExport()
    {
        var system = SystemWithOrphan();
        system.FolderCheck = new Problem("BackupFolderWritable", Folder, "S-1-5-32-545");
        var outcome = Run(system);
        Assert.Equal("BackupFolderWritable", outcome.Problem!.Code);
        Assert.DoesNotContain(system.Calls, c => c.StartsWith("Export", StringComparison.Ordinal));
        Assert.Single(system.Keys);

        system = SystemWithOrphan();
        system.FolderCreate = new Problem("BackupFolderCreateFailed", Folder, 5);
        Assert.Equal("BackupFolderCreateFailed", Run(system).Problem!.Code);
        Assert.DoesNotContain("CheckFolder", system.Calls);
    }

    [Fact]
    public void AFailedExportLeavesTheKeyAndNoFiles()
    {
        var system = SystemWithOrphan();
        system.ExportExit = 1;
        var outcome = Run(system);
        Assert.Equal("RemoveEntryExportFailed", outcome.Problem!.Code);
        Assert.Equal(new object[] { 1 }, outcome.Problem.Args);
        Assert.Single(system.Keys);
        Assert.Empty(system.Files);
    }

    [Theory]
    [InlineData("other-key", "BackupKeyMismatch")]
    [InlineData("delete-line", "BackupDeleteLine")]
    [InlineData("outside", "BackupKeyOutside")]
    [InlineData("no-bom", "BackupBadEncoding")]
    [InlineData("empty", "BackupEmpty")]
    public void TheStagedExportIsCheckedWithTheBackupPrefixAndNothingIsKept(string kind, string code)
    {
        var system = SystemWithOrphan();
        system.ExportBytes = key => kind switch
        {
            "other-key" => Reg(Machine + @"\Other"),
            "delete-line" => Reg(key, "[-" + Machine + "\\Other]\r\n"),
            "outside" => Reg(key, "\r\n[" + Machine + "\\Other]\r\n"),
            "no-bom" => Encoding.Unicode.GetBytes("Windows Registry Editor Version 5.00\r\n\r\n[" + key + "]\r\n"),
            _ => Array.Empty<byte>(),
        };
        var outcome = Run(system);
        Assert.Equal(code, outcome.Problem!.Code);
        Assert.Single(system.Keys);
        Assert.Empty(system.Files);
        Assert.DoesNotContain("Write " + Id + ".reg", system.Calls);
    }

    [Fact]
    public void TheStagedFileMayBelongToTheUserButNobodyElseMayWriteIt()
    {
        var system = SystemWithOrphan();
        system.FileInfoFor = path => path.EndsWith(".tmp", StringComparison.Ordinal)
            ? new BackupFileInfo { LinkCount = 1, OwnerSid = "S-1-5-21-1-2-3-1001", WriteAccessSids = new[] { Admins } }
            : null!;
        Assert.True(Run(system).Removed);

        system = SystemWithOrphan();
        system.FileInfoFor = path => path.EndsWith(".tmp", StringComparison.Ordinal)
            ? new BackupFileInfo { LinkCount = 1, OwnerSid = Admins, WriteAccessSids = new[] { Admins, "S-1-5-32-545" } }
            : null!;
        Assert.Equal("BackupFileWritable", Run(system).Problem!.Code);
        Assert.Single(system.Keys);

        system = SystemWithOrphan();
        system.FileInfoFor = path => path.EndsWith(".tmp", StringComparison.Ordinal) ? new BackupFileInfo { LinkCount = 2, OwnerSid = Admins } : null!;
        Assert.Equal("BackupFileHardLinked", Run(system).Problem!.Code);
    }

    [Fact]
    public void TheFinalFileMustBelongToAdministratorsOtherwiseItIsRemovedAgain()
    {
        var system = SystemWithOrphan();
        system.FileInfoFor = path => path.EndsWith(".reg", StringComparison.Ordinal)
            ? new BackupFileInfo { LinkCount = 1, OwnerSid = "S-1-5-21-1-2-3-1001", WriteAccessSids = new[] { Admins } }
            : null!;
        var outcome = Run(system);
        Assert.Equal("BackupFileBadOwner", outcome.Problem!.Code);
        Assert.Empty(system.Files);
        Assert.Single(system.Keys);
    }

    [Fact]
    public void AFinalFileWithOtherBytesThanTheCheckedExportIsRefused()
    {
        var system = SystemWithOrphan();
        system.AfterWrite = (path, bytes) => path.EndsWith(".reg", StringComparison.Ordinal) ? Reg(Machine + @"\OldApp", "\"UninstallString\"=\"evil.exe\"\r\n") : bytes;
        Assert.Equal("BackupFileMismatch", Run(system).Problem!.Code);
        Assert.Empty(system.Files);
        Assert.Single(system.Keys);
    }

    [Fact]
    public void AnExistingBackupWithTheSameIdIsNeitherOverwrittenNorDeleted()
    {
        var system = SystemWithOrphan();
        var existing = Path.Combine(Folder, Id + ".reg");
        system.Files[existing] = new byte[] { 1, 2, 3 };
        var outcome = Run(system);
        Assert.Equal("RemoveEntryBackupWriteFailed", outcome.Problem!.Code);
        Assert.Equal(new byte[] { 1, 2, 3 }, system.Files[existing]);
        Assert.Single(system.Keys);
    }

    [Fact]
    public void WithoutASidecarTheBackupIsRemovedAndTheKeyStays()
    {
        var system = SystemWithOrphan();
        system.SidecarWriteFails = true;
        Assert.Equal("RemoveEntryBackupWriteFailed", Run(system).Problem!.Code);
        Assert.Empty(system.Files);
        Assert.Single(system.Keys);
    }

    [Fact]
    public void AnUnexpectedErrorAfterWritingTheBackupLeavesNoHalfBackupAndTheKey()
    {
        var system = SystemWithOrphan();
        system.ReadingTheFinalFileThrowsUnexpectedly = true;
        Assert.Throws<NotSupportedException>(() => Run(system));
        Assert.Empty(system.Files);
        Assert.Single(system.Keys);
    }

    [Theory]
    [InlineData(null, "OldApp")]
    [InlineData("   ", "OldApp")]
    [InlineData(" Old App ", "Old App")]
    public void TheSidecarAlwaysHasAName(string? displayName, string expected)
    {
        var system = SystemWithOrphan();
        system.Keys[Machine + @"\OldApp"].DisplayName = displayName!;
        Run(system);
        using var doc = JsonDocument.Parse(system.Files[Path.Combine(Folder, Id + ".json")]);
        Assert.Equal(expected, doc.RootElement.GetProperty("Name").GetString());
    }

    [Fact]
    public void ALongNameIsShortenedSoTheSidecarStaysSmall()
    {
        var system = SystemWithOrphan();
        system.Keys[Machine + @"\OldApp"].DisplayName = new string((char)0x00E4, 5000);
        Run(system);
        var bytes = system.Files[Path.Combine(Folder, Id + ".json")];
        using var doc = JsonDocument.Parse(bytes);
        Assert.Equal(RegistryRemoval.MaxNameLength, doc.RootElement.GetProperty("Name").GetString()!.Length);
        Assert.True(bytes.Length < 64 * 1024);
    }

    [Fact]
    public void ALineBreakAfterTheIdOrKeyIsNotAccepted()
    {
        var system = SystemWithOrphan();
        Assert.Equal("RemoveEntryBadActionId", Run(system, id: Id + "\n").Problem!.Code);
        // Mit \z gehört der Zeilenumbruch zum Namen und ist dort ein Steuerzeichen.
        Assert.Equal("BackupKeyNameUnsafe", Run(system, PlanKey + "\n").Problem!.Code);
        Assert.Empty(system.Calls);
    }

    [Fact]
    public void AFailedDeleteKeepsTheBackupAndSaysSo()
    {
        var system = SystemWithOrphan();
        system.DeleteKeyThrows = true;
        var outcome = Run(system);
        Assert.Equal("RemoveEntryDeleteFailed", outcome.Problem!.Code);
        Assert.False(outcome.Removed);
        Assert.Equal(2, system.Files.Count);

        system = SystemWithOrphan();
        system.KeyStaysAfterDelete = true;
        outcome = Run(system);
        Assert.Equal("RemoveEntryDeleteFailed", outcome.Problem!.Code);
        Assert.False(outcome.Removed);
    }

    [Fact]
    public void TheReasonCodesMatchTheModule()
    {
        var module = File.ReadAllText(Path.Combine(RepoRoot(), "src", "SoftwareInventory", "Private", "RegistryBackup.ps1"));
        var line = module.Split('\n').Single(l => l.StartsWith("$script:KnownBackupReasonCodes", StringComparison.Ordinal));
        var codes = System.Text.RegularExpressions.Regex.Matches(line, "'([A-Za-z]+)'").Cast<System.Text.RegularExpressions.Match>().Select(m => m.Groups[1].Value).ToArray();
        Assert.Equal(codes, RegistryRemoval.KnownReasonCodes);
    }

    private static string RepoRoot([System.Runtime.CompilerServices.CallerFilePath] string sourceFile = "") =>
        Path.GetDirectoryName(Path.GetDirectoryName(Path.GetDirectoryName(sourceFile)!)!)!;
}
