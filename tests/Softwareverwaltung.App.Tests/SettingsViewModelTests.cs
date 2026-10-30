using System.Security;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;
using Softwareverwaltung.App.ViewModels;

namespace Softwareverwaltung.App.Tests;

public sealed class SettingsViewModelTests
{
    private static readonly string[] AllSwitches =
        ["RegistryMachine", "RegistryUser", "Winget", "Appx", "UserAssist", "Process", "Autostart", "ScheduledTask",
         "WingetSearch", "GitHub", "NVD", "CIRCL", "KEV", "EPSS", "RestorePoint"];

    private static AppSettings Off(params string[] on) => new()
    {
        Switches = AllSwitches.ToDictionary(s => s, s => on.Contains(s)),
    };

    [Fact]
    public async Task LoadsSavedStateWithoutBeingDirty()
    {
        var fake = new FakeSettings { Saved = Off("Winget", "NVD") with { Usage = "Private", ScanMode = "Folders", ScanPaths = ["C:\\Tools", "D:\\Portable"], LogMaxSizeMB = 250 } };
        var vm = new SettingsViewModel(fake);

        await vm.LoadAsync();

        Assert.True(vm.IsLoaded);
        Assert.False(vm.IsDirty);
        Assert.False(vm.NeedsUsageChoice);
        Assert.True(vm.IsPrivate);
        Assert.True(Switch(vm, "Winget").IsOn);
        Assert.True(Switch(vm, "NVD").IsOn);
        Assert.False(Switch(vm, "Appx").IsOn);
        Assert.Equal(["C:\\Tools", "D:\\Portable"], vm.ScanFolders);
        Assert.True(vm.IsFoldersMode);
        Assert.False(vm.IsDrivesMode);
        Assert.Equal(250, vm.LogMaxSizeMB);
        Assert.False(vm.SaveCommand.CanExecute(null));
    }

    [Fact]
    public async Task ShowsEveryModuleSwitch()
    {
        var vm = new SettingsViewModel(new FakeSettings());
        await vm.LoadAsync();

        var shown = vm.Sources.Concat(vm.Traces).Concat(vm.Services).Concat(vm.Actions).Select(s => s.Name);
        Assert.Equal(AllSwitches.Order(), shown.Order());
        Assert.All(vm.Services, s => Assert.False(string.IsNullOrWhiteSpace(s.Description)));
    }

    [Theory]
    [InlineData("Private")]
    [InlineData("Company")]
    public async Task FirstStartChoiceShowsTermsAndSwitchesNothingOn(string usage)
    {
        var fake = new FakeSettings();
        var vm = new SettingsViewModel(fake);
        await vm.LoadAsync();
        Assert.True(vm.NeedsUsageChoice);
        Assert.True(vm.ShowFirstStartCard);
        Assert.Empty(vm.ServiceTerms);

        await vm.ChooseUsageCommand.ExecuteAsync(usage);

        Assert.False(vm.NeedsUsageChoice);
        Assert.Equal(["Usage:" + usage], fake.Calls);
        Assert.DoesNotContain(true, fake.Saved.Switches.Values);
        Assert.All(vm.Sources.Concat(vm.Traces).Concat(vm.Services).Concat(vm.Actions), s => Assert.False(s.IsOn));
        Assert.False(vm.IsDirty);

        // Danach die passenden Hinweise, bis „Verstanden“.
        Assert.True(vm.ShowTermsNotice);
        Assert.Equal("NVD", Assert.Single(vm.ServiceTerms).Service);
        Assert.Equal("Hinweis " + usage, vm.TermsGeneral);
        vm.AcknowledgeTermsCommand.Execute(null);
        Assert.False(vm.ShowFirstStartCard);
    }

    [Fact]
    public async Task UsageChoiceKeepsOtherUnsavedEditsOpen()
    {
        var fake = new FakeSettings();
        var vm = new SettingsViewModel(fake);
        await vm.LoadAsync();

        Switch(vm, "Appx").IsOn = true;
        await vm.ChooseUsageCommand.ExecuteAsync("Company");

        Assert.True(vm.IsCompany);
        Assert.True(vm.IsDirty);
        Assert.False(fake.Saved.Switches["Appx"]);
    }

    [Fact]
    public async Task SettingsShowTermsForSelectedUsage()
    {
        var vm = new SettingsViewModel(new FakeSettings { Saved = Off() with { Usage = "Private" } });
        await vm.LoadAsync();
        Assert.False(vm.ShowFirstStartCard);
        Assert.Equal("Hinweis Private", vm.TermsGeneral);

        vm.IsCompany = true;

        Assert.Equal("Hinweis Company", vm.TermsGeneral);
        Assert.NotNull(Assert.Single(vm.ServiceTerms).UsageHint);
    }

    [Fact]
    public async Task TracksChangesAndSavesOnlyOnRequest()
    {
        var fake = new FakeSettings();
        var vm = new SettingsViewModel(fake);
        await vm.LoadAsync();

        Switch(vm, "KEV").IsOn = true;
        Assert.True(vm.IsDirty);
        Switch(vm, "KEV").IsOn = false;
        Assert.False(vm.IsDirty);

        Switch(vm, "RegistryUser").IsOn = true;
        vm.ExcludePathsText = "  %USERPROFILE%\\Builds  \r\n\r\nE:\\Temp ";
        vm.LogRetentionDays = 14;
        Assert.Empty(fake.Calls);

        await vm.SaveCommand.ExecuteAsync(null);

        Assert.Equal(["Save"], fake.Calls);
        Assert.True(fake.Saved.Switches["RegistryUser"]);
        Assert.Equal(["%USERPROFILE%\\Builds", "E:\\Temp"], fake.Saved.ExcludePaths);
        Assert.Equal(14, fake.Saved.LogRetentionDays);
        Assert.False(vm.IsDirty);
        Assert.Contains("Gespeichert", vm.StatusText);
    }

    [Fact]
    public async Task PortableSearchSwitchLoadsTracksAndSavesWithoutTouchingTraces()
    {
        var fake = new FakeSettings { Saved = Off("UserAssist") with { ScanPaths = ["%USERPROFILE%"] } };
        var vm = new SettingsViewModel(fake);
        await vm.LoadAsync();
        Assert.False(vm.PortableSearchEnabled);

        vm.PortableSearchEnabled = true;
        Assert.True(vm.IsDirty);
        await vm.SaveCommand.ExecuteAsync(null);

        Assert.True(fake.Saved.PortableSearch);
        Assert.True(fake.Saved.Switches["UserAssist"]);
        Assert.Equal(["%USERPROFILE%"], fake.Saved.ScanPaths);
        Assert.False(vm.IsDirty);
    }

    [Fact]
    public async Task DiscardRestoresSavedState()
    {
        var vm = new SettingsViewModel(new FakeSettings { Saved = Off("Winget") });
        await vm.LoadAsync();

        Switch(vm, "Winget").IsOn = false;
        vm.ComputeHash = true;
        vm.DiscardCommand.Execute(null);

        Assert.True(Switch(vm, "Winget").IsOn);
        Assert.False(vm.ComputeHash);
        Assert.False(vm.IsDirty);
    }

    [Fact]
    public async Task PresetPrefillsWithoutSavingOrTouchingServices()
    {
        var fake = new FakeSettings
        {
            Preset = new SettingPreset(["RegistryMachine", "Winget", "UserAssist"], [], ["C:"], IncludeTemp: true, ComputeHash: true, ScanMode: "Drives"),
        };
        var vm = new SettingsViewModel(fake);
        await vm.LoadAsync();

        await vm.ApplyPresetCommand.ExecuteAsync("Thorough");

        Assert.Equal(["Preset:Thorough"], fake.Calls);
        Assert.True(vm.IsDirty);
        Assert.True(Switch(vm, "Winget").IsOn);
        Assert.True(Switch(vm, "UserAssist").IsOn);
        Assert.All(vm.Services, s => Assert.False(s.IsOn));
        Assert.True(Assert.Single(vm.Drives, d => d.Drive == "C:").IsSelected);
        Assert.True(vm.IncludeTemp);
        Assert.True(vm.ComputeHash);
        // Nie den Hauptschalter, und jede Änderung wird sichtbar genannt.
        Assert.False(vm.PortableSearchEnabled);
        Assert.StartsWith("Vorlage „Gründlich“ hat gesetzt:", vm.StatusText);
        Assert.True(vm.IsDrivesMode);
        foreach (var expected in new[] { "Wo suchen: Ganze Laufwerke", "Programme für alle Benutzer: An", "winget-Paketliste: An", "Zuletzt gestartete Programme: An", "Laufwerk C:: An", "Temp-Ordner mit durchsuchen: An", "Prüfsumme (SHA256) berechnen – langsamer: An" })
        {
            Assert.Contains(expected, vm.StatusText);
        }
        Assert.DoesNotContain("Laufwerk D:", vm.StatusText);
    }

    [Fact]
    public async Task PresetReportsWhenNothingChanges()
    {
        var vm = new SettingsViewModel(new FakeSettings { Preset = new SettingPreset([], [], [], false, false) });
        await vm.LoadAsync();

        await vm.ApplyPresetCommand.ExecuteAsync("Quick");

        Assert.Equal("Vorlage „Schnell“: keine Änderung, alles war schon so eingestellt.", vm.StatusText);
        Assert.False(vm.IsDirty);
    }

    [Fact]
    public async Task NothingIsPreselectedAndHintShowsWithoutOptionOrEntry()
    {
        var vm = new SettingsViewModel(new FakeSettings());
        await vm.LoadAsync();

        Assert.Null(vm.ScanMode);
        Assert.False(vm.IsDrivesMode);
        Assert.False(vm.IsFoldersMode);
        Assert.Empty(vm.ScanFolders);
        Assert.All(vm.Drives, d => Assert.False(d.IsSelected));
        Assert.Contains(vm.Drives, d => d.Drive == "E:" && d.Text.Contains("USB"));
        Assert.False(vm.NoScanLocation);   // Suche aus: kein Hinweis

        vm.PortableSearchEnabled = true;
        Assert.False(vm.NoScanLocation);   // Dateisuche noch aus: kein Hinweis
        vm.FileSearchEnabled = true;
        Assert.True(vm.NoScanLocation);    // keine Option gewählt

        vm.IsDrivesMode = true;
        Assert.True(vm.NoScanLocation);    // Option ohne Eintrag
        vm.Drives.Single(d => d.Drive == "D:").IsSelected = true;
        Assert.False(vm.NoScanLocation);

        vm.IsFoldersMode = true;
        Assert.True(vm.NoScanLocation);    // Laufwerk gespeichert, zählt aber in dieser Option nicht
        vm.AddFolderCommand.Execute(@"C:\Tools");
        Assert.False(vm.NoScanLocation);
    }

    [Fact]
    public async Task SwitchingOptionKeepsTheOtherSelectionAndSavesBoth()
    {
        var fake = new FakeSettings();
        var vm = new SettingsViewModel(fake);
        await vm.LoadAsync();

        vm.IsDrivesMode = true;
        vm.Drives.Single(d => d.Drive == "D:").IsSelected = true;
        vm.IsFoldersMode = true;
        vm.AddFolderCommand.Execute("%USERPROFILE%");

        Assert.True(vm.Drives.Single(d => d.Drive == "D:").IsSelected);
        await vm.SaveCommand.ExecuteAsync(null);
        Assert.Equal("Folders", fake.Saved.ScanMode);
        Assert.Equal(["%USERPROFILE%"], fake.Saved.ScanPaths);
        Assert.Equal(["D:"], fake.Saved.ScanDrives);
    }

    [Fact]
    public async Task DriveDurationHintShowsOnlyWithSelectedDrive()
    {
        var vm = new SettingsViewModel(new FakeSettings());
        await vm.LoadAsync();
        vm.PortableSearchEnabled = true;
        vm.FileSearchEnabled = true;

        vm.IsDrivesMode = true;
        Assert.False(vm.ShowDriveDurationHint);
        vm.Drives.Single(d => d.Drive == "C:").IsSelected = true;
        Assert.True(vm.ShowDriveDurationHint);
        vm.IsFoldersMode = true;
        Assert.False(vm.ShowDriveDurationHint);
    }

    [Fact]
    public async Task FoldersAreAddedFromSuggestionsAndPickerAndCanBeRemoved()
    {
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var picker = new FakeFolderPicker { Next = Path.Combine(profile, "Tools") };
        var vm = new SettingsViewModel(new FakeSettings(), picker);
        await vm.LoadAsync();
        Assert.Equal(["%USERPROFILE%", @"%USERPROFILE%\Downloads"], vm.FolderSuggestions);

        vm.AddFolderCommand.Execute("%USERPROFILE%");
        vm.AddFolderCommand.Execute("%userprofile%");          // doppelt, egal welche Schreibweise
        Assert.Equal([@"%USERPROFILE%\Downloads"], vm.FolderSuggestions);

        vm.PickFolderCommand.Execute(null);                     // Profilordner wird als %USERPROFILE%\… gespeichert
        picker.Next = @"D:\Portable";
        vm.PickFolderCommand.Execute(null);
        picker.Next = null;                                     // Dialog abgebrochen
        vm.PickFolderCommand.Execute(null);
        Assert.Equal(["%USERPROFILE%", @"%USERPROFILE%\Tools", @"D:\Portable"], vm.ScanFolders);

        vm.RemoveFolderCommand.Execute(@"%USERPROFILE%\Tools");
        Assert.Equal(["%USERPROFILE%", @"D:\Portable"], vm.ScanFolders);
        Assert.True(vm.IsDirty);
    }

    [Fact]
    public async Task QuickPresetSetsFolderOptionAndEntriesButLeavesDrives()
    {
        var fake = new FakeSettings
        {
            Saved = Off() with { ScanDrives = ["D:"] },
            Preset = new SettingPreset([], ["%USERPROFILE%"], [], IncludeTemp: false, ComputeHash: false, ScanMode: "Folders"),
        };
        var vm = new SettingsViewModel(fake);
        await vm.LoadAsync();

        await vm.ApplyPresetCommand.ExecuteAsync("Quick");

        Assert.True(vm.IsFoldersMode);
        Assert.Equal(["%USERPROFILE%"], vm.ScanFolders);
        Assert.True(vm.Drives.Single(d => d.Drive == "D:").IsSelected);
        Assert.Contains("Wo suchen: Nur bestimmte Ordner", vm.StatusText);
        Assert.Contains("Ordner: %USERPROFILE%", vm.StatusText);
        Assert.False(vm.PortableSearchEnabled);
    }

    [Fact]
    public async Task TraceAndFileSearchAreIndependentSwitchesAndAreSaved()
    {
        var fake = new FakeSettings();
        var vm = new SettingsViewModel(fake);
        await vm.LoadAsync();
        Assert.False(vm.TraceSearchEnabled);
        Assert.False(vm.FileSearchEnabled);

        vm.PortableSearchEnabled = true;
        vm.TraceSearchEnabled = true;
        Switch(vm, "Process").IsOn = true;
        await vm.SaveCommand.ExecuteAsync(null);

        Assert.True(fake.Saved.PortableSearch);
        Assert.True(fake.Saved.TraceSearch);
        Assert.False(fake.Saved.FileSearch);
        Assert.False(vm.NoScanLocation);   // ohne Dateisuche kein Hinweis auf fehlende Laufwerke/Ordner
    }

    [Fact]
    public async Task DriveListFollowsPluggedAndUnpluggedDrivesWithoutLosingSelection()
    {
        var fake = new FakeSettings { Saved = Off() with { ScanMode = "Drives", ScanDrives = ["E:"] } };
        var vm = new SettingsViewModel(fake);
        await vm.LoadAsync();
        Assert.True(vm.Drives.Single(d => d.Drive == "E:").IsSelected);

        // USB-Stick E: abgezogen, F: angesteckt
        fake.DriveList.RemoveAll(d => d.Drive == "E:");
        fake.DriveList.Add(new("F:", "Neu", 64, false, "Removable"));
        await vm.RefreshDrivesAsync();

        var e = vm.Drives.Single(d => d.Drive == "E:");
        Assert.True(e.IsSelected);
        Assert.False(e.Available);
        Assert.Contains("nicht verbunden", e.Text);
        var f = vm.Drives.Single(d => d.Drive == "F:");
        Assert.False(f.IsSelected);
        Assert.Contains("USB", f.Text);
        Assert.False(vm.IsDirty);           // Auswahl unverändert, nichts zu speichern

        // E: wieder angesteckt: wieder normal und weiterhin gewählt
        fake.DriveList.Add(new("E:", "Stick", 32, false, "Removable"));
        await vm.RefreshDrivesAsync();
        Assert.True(vm.Drives.Single(d => d.Drive == "E:").Available);
        Assert.True(vm.Drives.Single(d => d.Drive == "E:").IsSelected);
    }

    [Fact]
    public async Task UnselectedDriveDisappearsWhenUnplugged()
    {
        var fake = new FakeSettings();
        var vm = new SettingsViewModel(fake);
        await vm.LoadAsync();

        fake.DriveList.RemoveAll(d => d.Drive == "E:");
        await vm.RefreshDrivesAsync();

        Assert.DoesNotContain(vm.Drives, d => d.Drive == "E:");
    }

    private sealed class FakeFolderPicker : IFolderPicker
    {
        public string? Next { get; set; }

        public string? PickFolder() => Next;
    }

    [Fact]
    public async Task KeepsSavedDrivesThatAreNotConnected()
    {
        var vm = new SettingsViewModel(new FakeSettings { Saved = Off() with { ScanDrives = ["F:"] } });
        await vm.LoadAsync();

        var usb = Assert.Single(vm.Drives, d => d.Drive == "F:");
        Assert.True(usb.IsSelected);
        Assert.False(usb.Available);
        Assert.Contains("nicht verbunden", usb.Text);
        Assert.False(vm.IsDirty);
        Assert.Equal(["F:"], vm.Current.ScanDrives);
    }

    [Fact]
    public async Task ShowsSaveErrorsAndStaysDirty()
    {
        var fake = new FakeSettings { SaveFailure = new InvalidOperationException("LogRetentionDays ungültig") };
        var vm = new SettingsViewModel(fake);
        await vm.LoadAsync();

        vm.LogRetentionDays = 5000;
        await vm.SaveCommand.ExecuteAsync(null);

        Assert.Contains("LogRetentionDays ungültig", vm.ErrorText);
        Assert.True(vm.IsDirty);
    }

    [Fact]
    public async Task ShowsLoadErrors()
    {
        var vm = new SettingsViewModel(new FakeSettings { LoadFailure = new InvalidOperationException("Datei gesperrt") });

        await vm.LoadAsync();

        Assert.False(vm.IsLoaded);
        Assert.False(vm.NeedsUsageChoice);
        Assert.Contains("Datei gesperrt", vm.ErrorText);
    }

    [Fact]
    public async Task StoresAndRemovesCredentials()
    {
        var fake = new FakeSettings();
        var vm = new SettingsViewModel(fake);
        await vm.LoadAsync();
        var nvd = vm.Credentials.Single(c => c.Service == "NVD");
        Assert.Equal("Kein Schlüssel hinterlegt.", nvd.StatusText);

        await vm.SaveCredentialAsync(nvd, new SecureString());
        Assert.Contains("bitte einen Schlüssel eingeben", vm.ErrorText);

        using var secret = new SecureString();
        secret.AppendChar('x');
        await vm.SaveCredentialAsync(nvd, secret);
        Assert.True(nvd.Stored);
        Assert.Contains("Anmeldeinformationsverwaltung", nvd.StatusText);
        Assert.Null(vm.ErrorText);

        await vm.RemoveCredentialCommand.ExecuteAsync(nvd);
        Assert.False(nvd.Stored);
        Assert.Equal(["SetCredential:NVD", "RemoveCredential:NVD"], fake.Calls);
    }

    [Fact]
    public async Task ShowsCredentialFromEnvironment()
    {
        var vm = new SettingsViewModel(new FakeSettings { EnvironmentKeys = ["GitHub"] });
        await vm.LoadAsync();

        var github = vm.Credentials.Single(c => c.Service == "GitHub");
        Assert.False(github.Stored);
        Assert.Contains("GITHUB_TOKEN", github.StatusText);
    }

    private static SettingSwitch Switch(SettingsViewModel vm, string name) =>
        vm.Sources.Concat(vm.Traces).Concat(vm.Services).Concat(vm.Actions).Single(s => s.Name == name);

    private sealed class FakeSettings : ISettingsService
    {
        private readonly HashSet<string> _stored = [];

        public AppSettings Saved { get; set; } = Off();
        public SettingPreset Preset { get; set; } = new([], [], [], false, false);
        public IReadOnlyList<string> EnvironmentKeys { get; set; } = [];
        public Exception? LoadFailure { get; set; }
        public Exception? SaveFailure { get; set; }
        public List<string> Calls { get; } = [];

        public Task<AppSettings> LoadAsync(CancellationToken cancellationToken = default) =>
            LoadFailure is null ? Task.FromResult(Saved) : Task.FromException<AppSettings>(LoadFailure);

        public Task<AppSettings> SaveAsync(AppSettings settings, CancellationToken cancellationToken = default)
        {
            Calls.Add("Save");
            if (SaveFailure is not null)
            {
                return Task.FromException<AppSettings>(SaveFailure);
            }
            Saved = settings;
            return Task.FromResult(Saved);
        }

        public Task<AppSettings> SaveUsageAsync(string usage, CancellationToken cancellationToken = default)
        {
            Calls.Add("Usage:" + usage);
            Saved = Saved with { Usage = usage };
            return Task.FromResult(Saved);
        }

        public Task<SettingPreset> GetPresetAsync(string preset, CancellationToken cancellationToken = default)
        {
            Calls.Add("Preset:" + preset);
            return Task.FromResult(Preset);
        }

        public List<ScanDrive> DriveList { get; } = [new("C:", "System", 500, true, "Fixed"), new("D:", null, 1000, true, "Fixed"), new("E:", "Stick", 32, false, "Removable")];

        public Task<IReadOnlyList<ScanDrive>> GetDrivesAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<ScanDrive>>(DriveList.ToList());

        public Task<IReadOnlyList<ServiceTermsNotice>> GetServiceTermsAsync(string usage, CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<ServiceTermsNotice>>(
                [new("NVD", "NVD", "Kostenlos.", usage == "Company" ? "Richtlinien prüfen." : null, new Uri("https://nvd.nist.gov/developers/terms-of-use"), "Hinweis " + usage)]);

        public Task<IReadOnlyList<CredentialStatus>> GetCredentialStatusAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<CredentialStatus>>([Status("NVD"), Status("GitHub")]);

        public Task<CredentialStatus> SetCredentialAsync(string service, SecureString secret, CancellationToken cancellationToken = default)
        {
            Calls.Add("SetCredential:" + service);
            _stored.Add(service);
            return Task.FromResult(Status(service));
        }

        public Task<CredentialStatus> RemoveCredentialAsync(string service, CancellationToken cancellationToken = default)
        {
            Calls.Add("RemoveCredential:" + service);
            _stored.Remove(service);
            return Task.FromResult(Status(service));
        }

        private CredentialStatus Status(string service)
        {
            var stored = _stored.Contains(service);
            var env = EnvironmentKeys.Contains(service);
            return new(service, stored, service == "NVD" ? "NVD_API_KEY" : "GITHUB_TOKEN", env,
                stored ? "CredentialManager" : env ? "Environment" : null);
        }
    }
}
