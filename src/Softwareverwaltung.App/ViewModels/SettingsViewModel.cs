using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Security;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;

namespace Softwareverwaltung.App.ViewModels;

/// <summary>Ein Schalter der Einstellungen. Name ist der Modulname, Label und Description sind für den Benutzer.</summary>
public sealed partial class SettingSwitch(string name, string label, string description) : ObservableObject
{
    public string Name { get; } = name;
    public string Label { get; } = label;
    public string Description { get; } = description;

    [ObservableProperty]
    private bool _isOn;
}

/// <summary>Laufwerk für den Dateiscan; Available ist false, wenn ein gespeichertes Laufwerk gerade fehlt.</summary>
public sealed partial class DriveOption(string drive, string text, bool available) : ObservableObject
{
    public string Drive { get; } = drive;
    public string Text { get; } = text;
    public bool Available { get; } = available;

    [ObservableProperty]
    private bool _isSelected;
}

/// <summary>API-Schlüssel eines Dienstes. Der Schlüssel selbst landet nie im ViewModel.</summary>
public sealed partial class CredentialItem(string service, string title, string description) : ObservableObject
{
    public string Service { get; } = service;
    public string Title { get; } = title;
    public string Description { get; } = description;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(StatusText))]
    private CredentialStatus? _status;

    public bool Stored => Status?.Stored ?? false;

    public string StatusText => Status switch
    {
        null => "Status unbekannt.",
        { Stored: true, EnvironmentSet: true } => $"In der Windows-Anmeldeinformationsverwaltung gespeichert (hat Vorrang vor {Status.EnvironmentVariable}).",
        { Stored: true } => "In der Windows-Anmeldeinformationsverwaltung gespeichert.",
        { EnvironmentSet: true } => $"Kommt aus der Umgebungsvariablen {Status.EnvironmentVariable}.",
        _ => "Kein Schlüssel hinterlegt.",
    };

    partial void OnStatusChanged(CredentialStatus? value) => OnPropertyChanged(nameof(Stored));
}

/// <summary>
/// Einstellungsseite. Änderungen gelten erst nach „Speichern“; „Verwerfen“ lädt den gespeicherten Stand.
/// Vorlagen belegen nur vor. Privat/Firma ist reine Information und wird sofort gespeichert.
/// </summary>
public sealed partial class SettingsViewModel : ObservableObject
{
    private readonly ISettingsService _settings;
    private AppSettings _saved = new();
    private bool _loading;

    public SettingsViewModel(ISettingsService settings)
    {
        _settings = settings;
        Sources =
        [
            new("RegistryMachine", "Programme für alle Benutzer", "Installierte Programme aus der Registry (HKLM)."),
            new("RegistryUser", "Programme nur für mich", "Installierte Programme des angemeldeten Benutzers (HKCU)."),
            new("Winget", "winget-Paketliste", "Programme, die winget kennt, mit Paket-ID für Updates."),
            new("Appx", "Store-Apps", "Apps aus dem Microsoft Store und andere App-Pakete."),
        ];
        Traces =
        [
            new("UserAssist", "Zuletzt gestartete Programme", "Startzähler des Windows-Explorers (UserAssist)."),
            new("Process", "Laufende Prozesse", "Programme, die gerade laufen."),
            new("Autostart", "Autostart-Einträge", "Programme, die beim Anmelden starten."),
            new("ScheduledTask", "Geplante Aufgaben", "Programme, die die Aufgabenplanung startet."),
        ];
        Services =
        [
            new("WingetSearch", "winget-Suche nach neuen Versionen", "Sendet Paket-IDs oder Programmnamen an die winget-Quellen (Microsoft)."),
            new("GitHub", "Neueste Releases auf GitHub", "Sendet den Namen des GitHub-Projekts (nur für Programme aus dem Katalog)."),
            new("NVD", "Sicherheitslücken (NIST NVD)", "Sendet Hersteller, Produkt und Version (CPE) an die National Vulnerability Database der USA."),
            new("KEV", "Aktiv ausgenutzte Lücken (CISA KEV)", "Lädt die öffentliche Liste herunter; sendet nichts über Ihre Programme."),
            new("EPSS", "Ausnutzungswahrscheinlichkeit (FIRST EPSS)", "Sendet die Nummern gefundener Sicherheitslücken (CVE-IDs)."),
        ];
        Actions =
        [
            new("RestorePoint", "Wiederherstellungspunkt vor jeder Aktion", "Legt vor dem Aktualisieren oder Deinstallieren einen Windows-Wiederherstellungspunkt an (eigene Administratorabfrage)."),
        ];
        Credentials =
        [
            new("NVD", "NVD-API-Schlüssel", "Optional. Ohne Schlüssel funktioniert die NVD-Abfrage, ist aber deutlich langsamer."),
            new("GitHub", "GitHub-Token", "Optional. Erhöht die Zahl erlaubter Abfragen bei GitHub."),
        ];
        foreach (var item in AllSwitches)
        {
            item.PropertyChanged += OnEditChanged;
        }
    }

    public IReadOnlyList<SettingSwitch> Sources { get; }
    public IReadOnlyList<SettingSwitch> Traces { get; }
    public IReadOnlyList<SettingSwitch> Services { get; }
    public IReadOnlyList<SettingSwitch> Actions { get; }
    public IReadOnlyList<CredentialItem> Credentials { get; }
    public ObservableCollection<DriveOption> Drives { get; } = [];

    private IEnumerable<SettingSwitch> AllSwitches => Sources.Concat(Traces).Concat(Services).Concat(Actions);

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(NeedsUsageChoice), nameof(IsPrivate), nameof(IsCompany))]
    private string? _usage;

    /// <summary>Eine Zeile je Ordner; Umgebungsvariablen wie %USERPROFILE% erlaubt.</summary>
    [ObservableProperty]
    private string _scanPathsText = "";

    [ObservableProperty]
    private string _excludePathsText = "";

    [ObservableProperty]
    private bool _includeTemp;

    [ObservableProperty]
    private bool _computeHash;

    [ObservableProperty]
    private bool _smartExclusions = true;

    [ObservableProperty]
    private int _logRetentionDays = 30;

    [ObservableProperty]
    private int _logMaxSizeMB = 100;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(SaveCommand), nameof(DiscardCommand))]
    private bool _isDirty;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(SaveCommand), nameof(DiscardCommand), nameof(ApplyPresetCommand), nameof(ChooseUsageCommand), nameof(RemoveCredentialCommand))]
    private bool _isBusy;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(ApplyPresetCommand), nameof(ChooseUsageCommand), nameof(RemoveCredentialCommand))]
    private bool _isLoaded;

    [ObservableProperty]
    private string? _statusText;

    [ObservableProperty]
    private string? _errorText;

    /// <summary>Erster Start: Privat oder Firma wurde noch nicht gewählt.</summary>
    public bool NeedsUsageChoice => IsLoaded && Usage is null;

    public bool IsPrivate
    {
        get => Usage == "Private";
        set { if (value) { Usage = "Private"; } }
    }

    public bool IsCompany
    {
        get => Usage == "Company";
        set { if (value) { Usage = "Company"; } }
    }

    partial void OnIsLoadedChanged(bool value) => OnPropertyChanged(nameof(NeedsUsageChoice));

    partial void OnUsageChanged(string? value) => UpdateDirty();
    partial void OnScanPathsTextChanged(string value) => UpdateDirty();
    partial void OnExcludePathsTextChanged(string value) => UpdateDirty();
    partial void OnIncludeTempChanged(bool value) => UpdateDirty();
    partial void OnComputeHashChanged(bool value) => UpdateDirty();
    partial void OnSmartExclusionsChanged(bool value) => UpdateDirty();
    partial void OnLogRetentionDaysChanged(int value) => UpdateDirty();
    partial void OnLogMaxSizeMBChanged(int value) => UpdateDirty();

    /// <summary>Lädt Einstellungen, Laufwerke und Schlüsselstatus. Das Modul muss geladen sein.</summary>
    public async Task LoadAsync()
    {
        IsBusy = true;
        ErrorText = null;
        try
        {
            var saved = await _settings.LoadAsync();
            var drives = await _settings.GetDrivesAsync();
            var credentials = await _settings.GetCredentialStatusAsync();
            Drives.Clear();
            foreach (var drive in drives)
            {
                var option = new DriveOption(drive.Drive, string.IsNullOrWhiteSpace(drive.Label) ? $"{drive.Drive} ({drive.SizeGB} GB)" : $"{drive.Drive} {drive.Label} ({drive.SizeGB} GB)", true);
                option.PropertyChanged += OnEditChanged;
                Drives.Add(option);
            }
            foreach (var item in Credentials)
            {
                item.Status = credentials.FirstOrDefault(c => c.Service == item.Service);
            }
            Apply(saved);
            IsLoaded = true;
        }
        catch (Exception ex)
        {
            ErrorText = "Einstellungen konnten nicht geladen werden: " + ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }

    /// <summary>Der aktuelle Stand der Seite als Einstellungen, wie sie gespeichert würden.</summary>
    public AppSettings Current => new()
    {
        Usage = Usage,
        Switches = AllSwitches.ToDictionary(s => s.Name, s => s.IsOn, StringComparer.OrdinalIgnoreCase),
        ScanPaths = Lines(ScanPathsText),
        ScanDrives = Drives.Where(d => d.IsSelected).Select(d => d.Drive).ToList(),
        ExcludePaths = Lines(ExcludePathsText),
        IncludeTemp = IncludeTemp,
        ComputeHash = ComputeHash,
        SmartExclusions = SmartExclusions,
        LogRetentionDays = LogRetentionDays,
        LogMaxSizeMB = LogMaxSizeMB,
    };

    [RelayCommand(CanExecute = nameof(CanSave))]
    private async Task SaveAsync()
    {
        IsBusy = true;
        ErrorText = null;
        try
        {
            Apply(await _settings.SaveAsync(Current));
            StatusText = "Gespeichert. Ein neuer Scan unter „Programme“ übernimmt die Änderungen.";
        }
        catch (Exception ex)
        {
            ErrorText = "Speichern fehlgeschlagen: " + ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }

    private bool CanSave() => IsDirty && !IsBusy;

    [RelayCommand(CanExecute = nameof(CanSave))]
    private void Discard()
    {
        Apply(_saved);
        ErrorText = null;
        StatusText = "Änderungen verworfen.";
    }

    /// <summary>Belegt Quellen, Nutzungsspuren und Dateiscan mit einer Vorlage vor; gespeichert wird erst mit „Speichern“.</summary>
    [RelayCommand(CanExecute = nameof(CanEdit))]
    private async Task ApplyPresetAsync(string preset)
    {
        IsBusy = true;
        ErrorText = null;
        try
        {
            var values = await _settings.GetPresetAsync(preset);
            _loading = true;
            foreach (var item in AllSwitches.Where(s => values.Enable.Contains(s.Name, StringComparer.OrdinalIgnoreCase)))
            {
                item.IsOn = true;
            }
            ScanPathsText = string.Join(Environment.NewLine, values.ScanPaths);
            SelectDrives(values.ScanDrives);
            IncludeTemp = values.IncludeTemp;
            ComputeHash = values.ComputeHash;
            _loading = false;
            UpdateDirty();
            StatusText = "Vorlage übernommen. Prüfen und mit „Speichern“ bestätigen.";
        }
        catch (Exception ex)
        {
            ErrorText = "Vorlage konnte nicht geladen werden: " + ex.Message;
        }
        finally
        {
            _loading = false;
            IsBusy = false;
        }
    }

    private bool CanEdit() => IsLoaded && !IsBusy;

    /// <summary>Erster Start: speichert nur Privat/Firma. Schaltet nichts frei oder ab.</summary>
    [RelayCommand(CanExecute = nameof(CanEdit))]
    private async Task ChooseUsageAsync(string usage)
    {
        IsBusy = true;
        ErrorText = null;
        try
        {
            var saved = await _settings.SaveUsageAsync(usage);
            _saved = _saved with { Usage = saved.Usage };
            Usage = saved.Usage;
            UpdateDirty();
        }
        catch (Exception ex)
        {
            ErrorText = "Speichern fehlgeschlagen: " + ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }

    /// <summary>Speichert einen Schlüssel aus einem Passwortfeld; der Aufrufer leert das Feld danach.</summary>
    public async Task SaveCredentialAsync(CredentialItem item, SecureString secret)
    {
        if (secret.Length == 0)
        {
            ErrorText = $"{item.Title}: bitte einen Schlüssel eingeben.";
            return;
        }
        IsBusy = true;
        ErrorText = null;
        try
        {
            item.Status = await _settings.SetCredentialAsync(item.Service, secret);
            StatusText = $"{item.Title} gespeichert.";
        }
        catch (Exception ex)
        {
            ErrorText = $"{item.Title} konnte nicht gespeichert werden: {ex.Message}";
        }
        finally
        {
            IsBusy = false;
        }
    }

    [RelayCommand(CanExecute = nameof(CanEdit))]
    private async Task RemoveCredentialAsync(CredentialItem item)
    {
        IsBusy = true;
        ErrorText = null;
        try
        {
            item.Status = await _settings.RemoveCredentialAsync(item.Service);
            StatusText = $"{item.Title} gelöscht.";
        }
        catch (Exception ex)
        {
            ErrorText = $"{item.Title} konnte nicht gelöscht werden: {ex.Message}";
        }
        finally
        {
            IsBusy = false;
        }
    }

    private void Apply(AppSettings settings)
    {
        _saved = settings;
        _loading = true;
        try
        {
            Usage = settings.Usage;
            foreach (var item in AllSwitches)
            {
                item.IsOn = settings.Switches.TryGetValue(item.Name, out var on) && on;
            }
            ScanPathsText = string.Join(Environment.NewLine, settings.ScanPaths);
            ExcludePathsText = string.Join(Environment.NewLine, settings.ExcludePaths);
            SelectDrives(settings.ScanDrives);
            IncludeTemp = settings.IncludeTemp;
            ComputeHash = settings.ComputeHash;
            SmartExclusions = settings.SmartExclusions;
            LogRetentionDays = settings.LogRetentionDays;
            LogMaxSizeMB = settings.LogMaxSizeMB;
        }
        finally
        {
            _loading = false;
        }
        UpdateDirty();
    }

    private void SelectDrives(IReadOnlyList<string> selected)
    {
        // Gespeicherte, aber gerade nicht verfügbare Laufwerke (z. B. USB) bleiben erhalten.
        foreach (var drive in selected.Where(d => !Drives.Any(o => string.Equals(o.Drive, d, StringComparison.OrdinalIgnoreCase))))
        {
            var option = new DriveOption(drive, $"{drive} (nicht verbunden)", false);
            option.PropertyChanged += OnEditChanged;
            Drives.Add(option);
        }
        foreach (var option in Drives)
        {
            option.IsSelected = selected.Contains(option.Drive, StringComparer.OrdinalIgnoreCase);
        }
    }

    private void OnEditChanged(object? sender, PropertyChangedEventArgs e) => UpdateDirty();

    private void UpdateDirty()
    {
        if (_loading)
        {
            return;
        }
        IsDirty = !SameSettings(Current, _saved);
    }

    private static bool SameSettings(AppSettings a, AppSettings b) =>
        a.Usage == b.Usage
        && a.Switches.All(s => (b.Switches.TryGetValue(s.Key, out var on) && on) == s.Value)
        && a.ScanPaths.SequenceEqual(b.ScanPaths, StringComparer.OrdinalIgnoreCase)
        && a.ScanDrives.Order(StringComparer.OrdinalIgnoreCase).SequenceEqual(b.ScanDrives.Order(StringComparer.OrdinalIgnoreCase), StringComparer.OrdinalIgnoreCase)
        && a.ExcludePaths.SequenceEqual(b.ExcludePaths, StringComparer.OrdinalIgnoreCase)
        && a.IncludeTemp == b.IncludeTemp
        && a.ComputeHash == b.ComputeHash
        && a.SmartExclusions == b.SmartExclusions
        && a.LogRetentionDays == b.LogRetentionDays
        && a.LogMaxSizeMB == b.LogMaxSizeMB;

    private static List<string> Lines(string text) =>
        text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();
}
