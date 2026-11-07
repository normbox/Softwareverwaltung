using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Text.Encodings.Web;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Softwareverwaltung.App.Advisor;
using Softwareverwaltung.App.Localization;
using Softwareverwaltung.App.Models;

namespace Softwareverwaltung.App.ViewModels;

/// <summary>Eine Freigabestufe als Auswahl (Radiobutton) mit kurzem Satz, was dazukommt.</summary>
public sealed partial class ShareLevelOption(int level, string title, string text) : ObservableObject
{
    public int Level { get; } = level;
    public string Title { get; } = title;
    public string Text { get; } = text;

    [ObservableProperty]
    private bool _isSelected;
}

/// <summary>
/// Abschnitt „KI-Berater“: Server, Modell, Schlüssel, Verbindungstest, Freigabestufe mit Vorschau.
/// Gespeichert wird mit dem gemeinsamen „Speichern“; Test, Modellliste und Vorschau nutzen die ungespeicherten Werte.
/// Es gibt kein Standardmodell: Das Feld bleibt leer, bis der Benutzer eines wählt.
/// </summary>
public sealed partial class SettingsViewModel
{
    private static readonly JsonSerializerOptions PreviewJson = new() { WriteIndented = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    private readonly IAdvisorService? _advisor;

    public ObservableCollection<AdvisorPresetInfo> AdvisorPresets { get; } = [];

    /// <summary>Modelle, die der Server zuletzt gemeldet hat; das Feld bleibt trotzdem frei editierbar.</summary>
    public ObservableCollection<string> AdvisorModels { get; } = [];

    public IReadOnlyList<ShareLevelOption> ShareLevels { get; private set; } = [];

    public CredentialItem AdvisorCredential { get; } = new("Advisor", AppText.Get("SettingsCredentialAdvisor"), AppText.Get("SettingsCredentialAdvisorText"));

    [ObservableProperty]
    private bool _advisorEnabled;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(AdvisorPresetNote), nameof(AdvisorPresetNeedsKey))]
    private string? _advisorPreset;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(LoadModelsCommand), nameof(TestConnectionCommand))]
    private string? _advisorEndpoint;

    [ObservableProperty]
    private string? _advisorModel;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowLevel4Hint))]
    private int _advisorShareLevelLocal = 3;

    /// <summary>Einmaliger Hinweis nach der Übernahme älterer Einstellungen (Stufe 2).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowShareLevelNoticeInMain))]
    private bool _showShareLevelNotice;

    /// <summary>Haken „Nicht mehr anzeigen“ am Hinweis: Nur dann speichert das Schließen dauerhaft.</summary>
    [ObservableProperty]
    private bool _dontShowShareLevelNoticeAgain;

    // ✕ ohne Haken: Hinweis nur für diese Sitzung ausgeblendet, auch nach späterem Speichern.
    private bool _shareLevelNoticeHiddenForSession;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(LoadModelsCommand), nameof(TestConnectionCommand))]
    private bool _isAdvisorBusy;

    [ObservableProperty]
    private string? _advisorResultText;

    /// <summary>Informational, Success, Warning oder Error (wie InfoBarSeverity).</summary>
    [ObservableProperty]
    private string _advisorResultSeverity = "Informational";

    /// <summary>Hinweis zur Adresse, z. B. „unverschlüsselt“ bei http im privaten Netz.</summary>
    [ObservableProperty]
    private string? _advisorEndpointNote;

    [ObservableProperty]
    private bool _isPreviewOpen;

    /// <summary>Eingerücktes JSON der Vorschau; null, solange es keine Daten gibt.</summary>
    [ObservableProperty]
    private string? _previewText;

    /// <summary>Hinweis statt Vorschau, z. B. vor dem ersten Scan oder bei einem Fehler.</summary>
    [ObservableProperty]
    private string? _previewHint;

    public string? AdvisorPresetNote => AdvisorPresets.FirstOrDefault(p => p.Name == AdvisorPreset)?.Note;

    public bool AdvisorPresetNeedsKey => AdvisorPresets.FirstOrDefault(p => p.Name == AdvisorPreset)?.RequiresApiKey == true;

    public bool ShowLevel4Hint => AdvisorShareLevelLocal == 4;

    /// <summary>Im Hauptfenster nur, wenn der Berater eingeschaltet ist; sonst nur hier in den Einstellungen.</summary>
    public bool ShowShareLevelNoticeInMain => ShowShareLevelNotice && _saved.AdvisorEnabled;

    /// <summary>Gespeichert eingeschaltet: Die Seitenleiste darf fragen (Adresse und Modell prüft das Modul beim Speichern).</summary>
    public bool IsAdvisorActive => _saved.AdvisorEnabled;

    /// <summary>
    /// Gespeicherte Werte, von denen ein laufendes Gespräch abhängt (Anbieter, Modell, Freigabestufe). Ändert sich
    /// der Wert, beginnt die Seitenleiste ein neues Gespräch.
    /// </summary>
    public string AdvisorSessionKey => string.Join('|', _saved.AdvisorEnabled, _saved.AdvisorPreset, _saved.AdvisorEndpoint, _saved.AdvisorModel, _saved.AdvisorShareLevelLocal);

    private AdvisorDraft Draft => new(AdvisorPreset, AdvisorEndpoint, AdvisorModel);

    private void InitializeAdvisor()
    {
        ShareLevels = Enumerable.Range(0, 5)
            .Select(level => new ShareLevelOption(level, AppText.Get($"SettingsAdvisorLevel{level}"), AppText.Get($"SettingsAdvisorLevel{level}Text")))
            .ToList();
        foreach (var option in ShareLevels)
        {
            option.PropertyChanged += OnShareLevelOptionChanged;
        }
        SelectShareLevelOption(AdvisorShareLevelLocal);
    }

    private void OnShareLevelOptionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(ShareLevelOption.IsSelected) && sender is ShareLevelOption { IsSelected: true } option)
        {
            AdvisorShareLevelLocal = option.Level;
        }
    }

    private void SelectShareLevelOption(int level)
    {
        foreach (var option in ShareLevels)
        {
            option.IsSelected = option.Level == level;
        }
    }

    partial void OnAdvisorEnabledChanged(bool value) => UpdateDirty();

    partial void OnAdvisorPresetChanged(string? value)
    {
        // Vorgabe belegt die Adresse nur vor (bei „Eigene Adresse“ bleibt sie); gespeichert wird mit „Speichern“.
        if (!_loading && AdvisorPresets.FirstOrDefault(p => p.Name == value)?.Endpoint is { } endpoint)
        {
            AdvisorEndpoint = endpoint;
        }
        UpdateDirty();
    }

    partial void OnAdvisorEndpointChanged(string? value)
    {
        AdvisorEndpointNote = null;
        UpdateDirty();
    }

    partial void OnAdvisorModelChanged(string? value) => UpdateDirty();

    partial void OnAdvisorShareLevelLocalChanged(int value)
    {
        SelectShareLevelOption(value);
        UpdateDirty();
        if (IsPreviewOpen)
        {
            _ = LoadPreviewAsync();
        }
    }

    partial void OnIsPreviewOpenChanged(bool value)
    {
        if (value)
        {
            _ = LoadPreviewAsync();
        }
    }

    private void ApplyAdvisor(AppSettings settings)
    {
        AdvisorEnabled = settings.AdvisorEnabled;
        AdvisorPreset = settings.AdvisorPreset;
        AdvisorEndpoint = settings.AdvisorEndpoint;
        AdvisorModel = settings.AdvisorModel;
        AdvisorShareLevelLocal = settings.AdvisorShareLevelLocal;
        ShowShareLevelNotice = settings.AdvisorShareLevelNoticePending && !_shareLevelNoticeHiddenForSession;
        OnPropertyChanged(nameof(ShowShareLevelNoticeInMain));
        OnPropertyChanged(nameof(IsAdvisorActive));
        OnPropertyChanged(nameof(AdvisorSessionKey));
    }

    private static bool SameAdvisor(AppSettings a, AppSettings b) =>
        a.AdvisorEnabled == b.AdvisorEnabled
        && a.AdvisorPreset == b.AdvisorPreset
        && (a.AdvisorEndpoint ?? "") == (b.AdvisorEndpoint ?? "")
        && (a.AdvisorModel ?? "") == (b.AdvisorModel ?? "")
        && a.AdvisorShareLevelLocal == b.AdvisorShareLevelLocal;

    private async Task LoadAdvisorPresetsAsync()
    {
        AdvisorPresets.Clear();
        foreach (var preset in await _settings.GetAdvisorPresetsAsync())
        {
            AdvisorPresets.Add(preset);
        }
    }

    private bool CanUseAdvisor() => _advisor is not null && IsLoaded && !IsAdvisorBusy && !string.IsNullOrWhiteSpace(AdvisorEndpoint);

    /// <summary>„Modelle laden“: füllt nur die Liste; ein Modell wählt der Benutzer selbst.</summary>
    [RelayCommand(CanExecute = nameof(CanUseAdvisor))]
    private async Task LoadModelsAsync()
    {
        IsAdvisorBusy = true;
        try
        {
            var result = await _advisor!.ListModelsAsync(Draft);
            ReplaceModels(result.Models);
            AdvisorEndpointNote = result.EndpointNote;
            ShowAdvisorResult(result.Models.Count == 0 ? "Warning" : "Informational",
                result.Models.Count == 0 ? AppText.Get("SettingsAdvisorNoModels") : AppText.Format("SettingsAdvisorModelsLoaded", result.Models.Count));
        }
        catch (AdvisorException ex)
        {
            ShowAdvisorResult("Error", ex.Message);
        }
        catch (Exception ex)
        {
            ShowAdvisorResult("Error", AppText.Format("SettingsAdvisorFailed", ex.Message));
        }
        finally
        {
            IsAdvisorBusy = false;
        }
    }

    /// <summary>„Verbindung testen“ mit den ungespeicherten Werten; nur auf Klick.</summary>
    [RelayCommand(CanExecute = nameof(CanUseAdvisor))]
    private async Task TestConnectionAsync()
    {
        IsAdvisorBusy = true;
        ShowAdvisorResult("Informational", AppText.Get("SettingsAdvisorTesting"));
        try
        {
            var result = await _advisor!.TestConnectionAsync(Draft);
            if (result.Models.Count > 0)
            {
                ReplaceModels(result.Models);
            }
            AdvisorEndpointNote = result.EndpointNote;
            ShowAdvisorResult(result.Ok ? "Success" : result.Warning ? "Warning" : "Error", result.Message);
        }
        catch (Exception ex)
        {
            ShowAdvisorResult("Error", AppText.Format("SettingsAdvisorFailed", ex.Message));
        }
        finally
        {
            IsAdvisorBusy = false;
        }
    }

    /// <summary>
    /// ✕ am Hinweis: ohne Haken „Nicht mehr anzeigen“ nur für diese Sitzung (beim nächsten Start erscheint er
    /// wieder), mit Haken dauerhaft gespeichert.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanEdit))]
    private async Task DismissShareLevelNoticeAsync()
    {
        if (!DontShowShareLevelNoticeAgain)
        {
            _shareLevelNoticeHiddenForSession = true;
            ShowShareLevelNotice = false;
            return;
        }
        try
        {
            var saved = await _settings.DismissShareLevelNoticeAsync();
            _saved = _saved with { AdvisorShareLevelNoticePending = saved.AdvisorShareLevelNoticePending };
            ShowShareLevelNotice = saved.AdvisorShareLevelNoticePending;
        }
        catch (Exception ex)
        {
            ErrorText = AppText.Format("SettingsSaveFailed", ex.Message);
        }
    }

    /// <summary>Vorschau für die gewählte (auch ungespeicherte) Stufe; ohne Scan nur ein Hinweis.</summary>
    public async Task LoadPreviewAsync()
    {
        if (_advisor is null)
        {
            return;
        }
        var level = AdvisorShareLevelLocal;
        try
        {
            var preview = await _advisor.GetPreviewAsync(level);
            if (level != AdvisorShareLevelLocal)
            {
                return;   // inzwischen andere Stufe gewählt; deren Vorschau kommt gleich
            }
            PreviewHint = preview.HasScanData ? null : AppText.Get("SettingsAdvisorPreviewNoScan");
            PreviewText = !preview.HasScanData
                ? null
                : string.Join(Environment.NewLine + Environment.NewLine,
                    new[] { ("get_inventory", (string?)preview.Inventory), ("get_program_details", preview.Details) }
                        .Where(p => p.Item2 is not null)
                        .Select(p => $"{p.Item1}{Environment.NewLine}{Pretty(p.Item2!)}"));
        }
        catch (Exception ex)
        {
            PreviewText = null;
            PreviewHint = AppText.Format("SettingsAdvisorFailed", ex.Message);
        }
    }

    private static string Pretty(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            return JsonSerializer.Serialize(doc.RootElement, PreviewJson);
        }
        catch (JsonException)
        {
            return json;
        }
    }

    private void ReplaceModels(IReadOnlyList<string> models)
    {
        var current = AdvisorModel;
        AdvisorModels.Clear();
        foreach (var model in models)
        {
            AdvisorModels.Add(model);
        }
        // Die Liste neu zu füllen darf die Eingabe nicht ändern (kein Standardmodell).
        AdvisorModel = current;
    }

    private void ShowAdvisorResult(string severity, string text)
    {
        AdvisorResultSeverity = severity;
        AdvisorResultText = text;
    }
}
