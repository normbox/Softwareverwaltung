using System.Text;
using SoftwareInventory.Helper;

namespace Softwareverwaltung.App.Tests;

/// <summary>
/// HKLM-Sicherungen im Admin-Ordner zurückspielen, löschen und bereinigen (Operationen RestoreRegistryBackup,
/// RemoveRegistryBackup, CleanupRegistryBackups), mit nachgebildetem System.
/// </summary>
public sealed class RegistryBackupStoreTests
{
    private const string Id = "0f8fad5b-d9cb-469f-a165-70867728950e";
    private const string Other = "1b4e28ba-2fa1-11d2-883f-0016d3cca427";
    private const string Folder = @"C:\Program Files\Softwareverwaltung\RegistryBackup";
    private const string Machine = @"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall";
    private const string Machine32 = @"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall";
    private const string Admins = "S-1-5-32-544";
    private static readonly DateTime Now = new(2026, 11, 17, 12, 0, 0, DateTimeKind.Utc);

    private sealed class FakeSystem : IRegistryBackupSystem
    {
        public bool Elevated { get; set; } = true;
        public string BackupFolder => Folder;
        public DateTime UtcNow => Now;
        public bool FolderExists { get; set; } = true;
        public Problem? FolderProblem { get; set; }
        public Dictionary<string, byte[]> Files { get; } = new(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, DateTime> Times { get; } = new(StringComparer.OrdinalIgnoreCase);
        public HashSet<string> Links { get; } = new(StringComparer.OrdinalIgnoreCase);
        public HashSet<string> Keys { get; } = new(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, BackupSidecar> Sidecars { get; } = new(StringComparer.OrdinalIgnoreCase);
        public Func<string, BackupFileInfo?>? InfoFor { get; set; }
        public HashSet<string> Undeletable { get; } = new(StringComparer.OrdinalIgnoreCase);
        public List<string> Calls { get; } = new();
        public int ImportExit { get; set; }
        public bool ImportCreatesKey { get; set; } = true;
        public Func<byte[], byte[]>? AfterWrite { get; set; }

        public bool BackupFolderExists() => FolderExists;
        public Problem CheckBackupFolder() => FolderProblem!;

        public BackupFileRead ReadFile(string path)
        {
            Calls.Add("Read " + Path.GetFileName(path));
            if (!Files.TryGetValue(path, out var bytes))
            {
                throw new FileNotFoundException();
            }
            var info = InfoFor?.Invoke(path) ?? new BackupFileInfo { LinkCount = 1, OwnerSid = Admins, WriteAccessSids = new[] { Admins } };
            return new BackupFileRead { Info = info, Size = bytes.Length, Bytes = bytes };
        }

        public BackupSidecar ReadSidecar(string path, out Problem fileProblem)
        {
            fileProblem = null!;
            if (!Files.ContainsKey(path))
            {
                throw new FileNotFoundException();
            }
            var info = InfoFor?.Invoke(path);
            if (info is not null)
            {
                fileProblem = BackupFileRules.CheckFile(path, info)!;
            }
            return Sidecars.TryGetValue(path, out var sidecar) ? sidecar : null!;
        }

        public void WriteNewFile(string path, byte[] bytes)
        {
            Calls.Add("Write " + Path.GetFileName(path));
            if (Files.ContainsKey(path))
            {
                throw new IOException("exists");
            }
            Files[path] = AfterWrite?.Invoke(bytes) ?? bytes;
        }

        public void DeleteFile(string path)
        {
            Calls.Add("Delete " + Path.GetFileName(path));
            if (!Undeletable.Contains(path))
            {
                Files.Remove(path);
            }
        }

        public bool FileExists(string path) => Files.ContainsKey(path);

        public int ImportFile(string path)
        {
            Calls.Add("Import " + Path.GetFileName(path));
            if (ImportExit == 0 && ImportCreatesKey)
            {
                Keys.Add(Machine + @"\App");
                Keys.Add(Machine32 + @"\App");
            }
            return ImportExit;
        }

        public bool KeyExists(string nativeKey) => Keys.Contains(nativeKey);

        public IReadOnlyList<BackupFolderEntry> ListFolder() => Files.Keys
            .Select(p => new BackupFolderEntry
            {
                Name = Path.GetFileName(p),
                IsReparsePoint = Links.Contains(p),
                LastWriteUtc = Times.TryGetValue(p, out var t) ? t : Now,
            })
            .ToList();
    }

    private static byte[] Reg(string body) =>
        new byte[] { 0xFF, 0xFE }.Concat(Encoding.Unicode.GetBytes("Windows Registry Editor Version 5.00\r\n\r\n" + body)).ToArray();

    private static string P(string name) => Path.Combine(Folder, name);

    private static FakeSystem WithBackup(string nativeKey = Machine + @"\App", string? body = null)
    {
        var system = new FakeSystem();
        system.Files[P(Id + ".reg")] = Reg(body ?? "[" + nativeKey + "]\r\n\"DisplayName\"=\"App\"\r\n\r\n[" + nativeKey + "\\Sub]\r\n\"A\"=dword:00000001\r\n");
        system.Files[P(Id + ".json")] = new byte[] { 1 };
        system.Sidecars[P(Id + ".json")] = new BackupSidecar { SchemaVersion = 1, ActionId = Id, NativeKey = nativeKey, Scope = "Machine" };
        return system;
    }

    [Fact]
    public void RestoresExactlyTheCheckedBytesThroughAnOwnFileAndRemovesIt()
    {
        var system = WithBackup();
        var outcome = RegistryBackupStore.Restore(Id, system);
        Assert.Null(outcome.Problem);
        Assert.True(outcome.Done);
        Assert.Equal(Machine + @"\App", outcome.NativeKey);
        Assert.Equal(
            new[] { "Read " + Id + ".reg", "Write " + Id + ".import.tmp", "Read " + Id + ".import.tmp", "Import " + Id + ".import.tmp", "Delete " + Id + ".import.tmp" },
            system.Calls);
        Assert.False(system.FileExists(P(Id + ".import.tmp")));
        Assert.True(system.FileExists(P(Id + ".reg")), "die Sicherung bleibt erhalten");
    }

    [Fact]
    public void RestoresA32BitEntryUnderWow6432Node()
    {
        var system = WithBackup(Machine32 + @"\App");
        Assert.True(RegistryBackupStore.Restore(Id, system).Done);
    }

    [Theory]
    [InlineData("delete-key", "BackupDeleteLine")]
    [InlineData("delete-value", "BackupDeleteLine")]
    [InlineData("delete-default", "BackupDeleteLine")]
    [InlineData("other-main", "BackupKeyOutside")]
    [InlineData("run-key", "BackupKeyOutside")]
    [InlineData("other-first", "BackupKeyMismatch")]
    [InlineData("user-key", "BackupKeyOutside")]
    public void OnlyTheKeyFromTheSidecarAndItsSubkeysWithoutDeleteLines(string kind, string code)
    {
        var key = Machine + @"\App";
        var body = kind switch
        {
            "delete-key" => "[" + key + "]\r\n\r\n[-" + Machine + "\\Other]\r\n",
            "delete-value" => "[" + key + "]\r\n\"UninstallString\"=-\r\n",
            "delete-default" => "[" + key + "]\r\n\r\n[" + key + "\\Sub]\r\n@=-\r\n",
            "other-main" => "[" + key + "]\r\n\r\n[" + Machine32 + "\\App]\r\n",
            "run-key" => "[" + key + "]\r\n\r\n[HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run]\r\n",
            "other-first" => "[" + Machine + "\\Other]\r\n",
            _ => "[" + key + "]\r\n\r\n[HKEY_CURRENT_USER\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\App]\r\n",
        };
        var system = WithBackup(key, body);
        var outcome = RegistryBackupStore.Restore(Id, system);
        Assert.Equal(code, outcome.Problem!.Code);
        Assert.DoesNotContain(system.Calls, c => c.StartsWith("Import", StringComparison.Ordinal) || c.StartsWith("Write", StringComparison.Ordinal));
    }

    [Theory]
    [InlineData(2, Id, "Machine", Machine + @"\App")]
    [InlineData(1, Other, "Machine", Machine + @"\App")]
    [InlineData(1, Id, "User", Machine + @"\App")]
    [InlineData(1, Id, "Machine", "")]
    public void TheSidecarMustMatchTheBackup(int schema, string actionId, string scope, string nativeKey)
    {
        var system = WithBackup();
        system.Sidecars[P(Id + ".json")] = new BackupSidecar { SchemaVersion = schema, ActionId = actionId, Scope = scope, NativeKey = nativeKey };
        Assert.Equal("BackupMetadataInvalid", RegistryBackupStore.Restore(Id, system).Problem!.Code);
    }

    [Fact]
    public void ASidecarForAnotherKeyIsAMismatch()
    {
        var system = WithBackup();
        system.Sidecars[P(Id + ".json")] = new BackupSidecar { SchemaVersion = 1, ActionId = Id, Scope = "Machine", NativeKey = Machine + @"\Other" };
        Assert.Equal("BackupKeyMismatch", RegistryBackupStore.Restore(Id, system).Problem!.Code);
    }

    [Fact]
    public void WithoutSidecarOrWithAnUnsafeKeyNameNothingIsRestored()
    {
        var system = WithBackup();
        system.Files.Remove(P(Id + ".json"));
        Assert.Equal("BackupMetadataMissing", RegistryBackupStore.Restore(Id, system).Problem!.Code);

        system = WithBackup();
        system.Sidecars[P(Id + ".json")].NativeKey = Machine + "\\Ap\"p";
        Assert.Equal("BackupKeyNameUnsafe", RegistryBackupStore.Restore(Id, system).Problem!.Code);
    }

    [Fact]
    public void FilesThatDoNotBelongToAdministratorsAreRefused()
    {
        var system = WithBackup();
        system.InfoFor = path => path.EndsWith(".reg", StringComparison.Ordinal) ? new BackupFileInfo { LinkCount = 1, OwnerSid = "S-1-5-21-1-2-3-1001", WriteAccessSids = new[] { Admins } } : null;
        Assert.Equal("BackupFileBadOwner", RegistryBackupStore.Restore(Id, system).Problem!.Code);

        system = WithBackup();
        system.InfoFor = path => path.EndsWith(".json", StringComparison.Ordinal) ? new BackupFileInfo { LinkCount = 1, OwnerSid = Admins, WriteAccessSids = new[] { Admins, "S-1-5-32-545" } } : null;
        Assert.Equal("BackupFileWritable", RegistryBackupStore.Restore(Id, system).Problem!.Code);
    }

    [Fact]
    public void AnExistingKeyIsNeverOverwritten()
    {
        var system = WithBackup();
        system.Keys.Add(Machine + @"\App");
        Assert.Equal("RestoreKeyExists", RegistryBackupStore.Restore(Id, system).Problem!.Code);
        Assert.DoesNotContain(system.Calls, c => c.StartsWith("Import", StringComparison.Ordinal));
    }

    [Fact]
    public void TheImportFileIsAlwaysRemovedAndAFailedImportIsReported()
    {
        var system = WithBackup();
        system.ImportExit = 1;
        Assert.Equal("RestoreBackupFailed", RegistryBackupStore.Restore(Id, system).Problem!.Code);
        Assert.False(system.FileExists(P(Id + ".import.tmp")));

        system = WithBackup();
        system.ImportCreatesKey = false;
        Assert.Equal("RestoreBackupFailed", RegistryBackupStore.Restore(Id, system).Problem!.Code);

        system = WithBackup();
        system.AfterWrite = _ => Reg("[" + Machine + "\\App]\r\n\"UninstallString\"=\"evil.exe\"\r\n");
        Assert.Equal("BackupFileMismatch", RegistryBackupStore.Restore(Id, system).Problem!.Code);
        Assert.False(system.FileExists(P(Id + ".import.tmp")));
    }

    [Fact]
    public void AnImportFileThatAlreadyExistsIsNotTouched()
    {
        var system = WithBackup();
        system.Files[P(Id + ".import.tmp")] = new byte[] { 9 };
        Assert.Equal("BackupImportWriteFailed", RegistryBackupStore.Restore(Id, system).Problem!.Code);
        Assert.Equal(new byte[] { 9 }, system.Files[P(Id + ".import.tmp")]);
    }

    [Theory]
    [InlineData("")]
    [InlineData("..\\x")]
    [InlineData("0f8fad5b-d9cb-469f-a165-70867728950e\\..\\x")]
    [InlineData("0f8fad5b-d9cb-469f-a165-70867728950e\n")]
    public void OnlyAGuidFindsABackup(string id)
    {
        var system = WithBackup();
        Assert.Equal("BackupBadId", RegistryBackupStore.Restore(id, system).Problem!.Code);
        Assert.Equal("BackupBadId", RegistryBackupStore.Remove(id, system).Problem!.Code);
        Assert.Empty(system.Calls);
    }

    [Fact]
    public void EverythingNeedsAdministratorRightsAndASoundFolder()
    {
        var system = WithBackup();
        system.Elevated = false;
        Assert.Equal("BackupNotElevated", RegistryBackupStore.Restore(Id, system).Problem!.Code);
        Assert.Equal("BackupNotElevated", RegistryBackupStore.Remove(Id, system).Problem!.Code);
        Assert.Equal("BackupNotElevated", RegistryBackupStore.Cleanup(system).Problem!.Code);

        system = WithBackup();
        system.FolderProblem = new Problem("BackupFolderOwnerRightsMissing", Folder);
        Assert.Equal("BackupFolderOwnerRightsMissing", RegistryBackupStore.Restore(Id, system).Problem!.Code);
        Assert.Equal("BackupFolderOwnerRightsMissing", RegistryBackupStore.Remove(Id, system).Problem!.Code);
        Assert.Equal("BackupFolderOwnerRightsMissing", RegistryBackupStore.Cleanup(system).Problem!.Code);
        Assert.Equal(2, system.Files.Count);
    }

    [Fact]
    public void RemovesTheBackupItsSidecarAndLeftoversOfThisIdOnly()
    {
        var system = WithBackup();
        system.Files[P(Id + ".tmp")] = new byte[] { 1 };
        system.Files[P(Other + ".reg")] = new byte[] { 1 };
        var outcome = RegistryBackupStore.Remove(Id, system);
        Assert.True(outcome.Done);
        Assert.Equal(3, outcome.Deleted);
        Assert.Equal(new[] { Other + ".reg" }, system.Files.Keys.Select(Path.GetFileName));
    }

    [Fact]
    public void RemovingAMissingOrStuckBackupIsReported()
    {
        var system = new FakeSystem();
        Assert.Equal("BackupNotFound", RegistryBackupStore.Remove(Id, system).Problem!.Code);

        system = WithBackup();
        system.Undeletable.Add(P(Id + ".json"));
        var outcome = RegistryBackupStore.Remove(Id, system);
        Assert.Equal("RemoveBackupFailed", outcome.Problem!.Code);
        Assert.Equal(new object[] { Id + ".json" }, outcome.Problem.Args);
        Assert.False(outcome.Done);

        system = WithBackup();
        system.FolderExists = false;
        Assert.Equal("BackupNotFound", RegistryBackupStore.Restore(Id, system).Problem!.Code);
    }

    [Fact]
    public void CleanupDeletesExpiredPairsOldLeftoversAndNothingElse()
    {
        var system = new FakeSystem();
        void Add(string name, TimeSpan age, bool link = false)
        {
            system.Files[P(name)] = new byte[] { 1 };
            system.Times[P(name)] = Now - age;
            if (link)
            {
                system.Links.Add(P(name));
            }
        }
        var expired = "11111111-1111-1111-1111-111111111111";
        var fresh = "22222222-2222-2222-2222-222222222222";
        var lonely = "33333333-3333-3333-3333-333333333333";
        var lonelyNew = "44444444-4444-4444-4444-444444444444";
        var linked = "55555555-5555-5555-5555-555555555555";
        Add(expired + ".reg", TimeSpan.FromDays(366));
        Add(expired + ".json", TimeSpan.FromDays(1));          // gehört zur abgelaufenen .reg: geht mit
        Add(fresh + ".reg", TimeSpan.FromDays(364));
        Add(fresh + ".json", TimeSpan.FromDays(400));          // gehört zu einer frischen .reg: bleibt
        Add(lonely + ".json", TimeSpan.FromDays(2));            // ohne .reg, älter als ein Tag
        Add(lonelyNew + ".json", TimeSpan.FromHours(2));        // ohne .reg, noch jung
        Add(fresh + ".tmp", TimeSpan.FromHours(2));             // Rest eines Laufs
        Add(fresh + ".import.tmp", TimeSpan.FromMinutes(10));  // läuft vielleicht gerade
        Add(linked + ".reg", TimeSpan.FromDays(900), link: true);
        Add("fremd.reg", TimeSpan.FromDays(900));
        Add("desktop.ini", TimeSpan.FromDays(900));

        var outcome = RegistryBackupStore.Cleanup(system);
        Assert.True(outcome.Done);
        Assert.Equal(4, outcome.Deleted);
        Assert.Equal(
            new[] { fresh + ".reg", fresh + ".json", lonelyNew + ".json", fresh + ".import.tmp", linked + ".reg", "fremd.reg", "desktop.ini" }.OrderBy(n => n, StringComparer.Ordinal),
            system.Files.Keys.Select(Path.GetFileName).OrderBy(n => n, StringComparer.Ordinal));
    }

    [Fact]
    public void CleanupKeepsABackupAtExactly365Days()
    {
        var system = new FakeSystem();
        system.Files[P(Id + ".reg")] = new byte[] { 1 };
        system.Times[P(Id + ".reg")] = Now - TimeSpan.FromDays(RegistryBackupStore.RetentionDays);
        Assert.Equal(0, RegistryBackupStore.Cleanup(system).Deleted);
        system.Times[P(Id + ".reg")] = Now - TimeSpan.FromDays(RegistryBackupStore.RetentionDays) - TimeSpan.FromMinutes(1);
        Assert.Equal(1, RegistryBackupStore.Cleanup(system).Deleted);
    }

    [Fact]
    public void CleanupWithoutAFolderHasNothingToDo()
    {
        var system = new FakeSystem { FolderExists = false };
        var outcome = RegistryBackupStore.Cleanup(system);
        Assert.True(outcome.Done);
        Assert.Null(outcome.Problem);
        Assert.Equal(0, outcome.Deleted);
    }

    [Fact]
    public void TheRetentionMatchesTheModule()
    {
        var module = File.ReadAllText(Path.Combine(RepoRoot(), "src", "SoftwareInventory", "Private", "RegistryBackup.ps1"));
        Assert.Contains("$script:RegistryBackupRetentionDays = " + RegistryBackupStore.RetentionDays, module);
    }

    private static string RepoRoot([System.Runtime.CompilerServices.CallerFilePath] string sourceFile = "") =>
        Path.GetDirectoryName(Path.GetDirectoryName(Path.GetDirectoryName(sourceFile)!)!)!;
}
