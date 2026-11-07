using System.Collections.ObjectModel;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Softwareverwaltung.App.Advisor;
using Softwareverwaltung.App.Localization;
using Softwareverwaltung.App.Services;

namespace Softwareverwaltung.App.ViewModels;

public enum AdvisorChatEntryKind
{
    User,
    Assistant,
    Info,
    Error,
}

/// <summary>Ein Eintrag im Verlauf der Seitenleiste. Detail ist bei Antworten die Zeile „Abgefragt: …“.</summary>
public sealed record AdvisorChatEntry(AdvisorChatEntryKind Kind, string Text, string? Detail = null)
{
    public bool IsUser => Kind == AdvisorChatEntryKind.User;

    public bool IsAssistant => Kind == AdvisorChatEntryKind.Assistant;

    public bool IsInfo => Kind == AdvisorChatEntryKind.Info;

    public bool IsError => Kind == AdvisorChatEntryKind.Error;
}

/// <summary>
/// Chat-Seitenleiste des KI-Beraters. Das Gespräch liegt nur im Speicher und verschwindet mit „Neues Gespräch“,
/// mit geänderten Beratereinstellungen oder beim Beenden; nichts wird auf die Festplatte geschrieben.
/// Fragen geht nur mit eingeschaltetem Berater, nach einem Scan und solange weder Scan noch Aktion laufen;
/// während einer Antwort sind umgekehrt Scan und Aktionen gesperrt (<see cref="MainViewModel.IsAdvisorBusy"/>).
/// Vorschläge des Modells führen nichts aus.
/// </summary>
public sealed partial class AdvisorChatViewModel : ObservableObject
{
    private readonly IAdvisorChatService? _service;
    private readonly MainViewModel _programs;
    private readonly SettingsViewModel _settings;
    private readonly IAppUiStore _ui;
    private IAdvisorChatSession? _session;
    private string _sessionKey;
    private bool _resetAfterAnswer;

    public AdvisorChatViewModel(IAdvisorChatService? service, MainViewModel programs, SettingsViewModel settings, IAppUiStore? ui = null)
    {
        _service = service;
        _programs = programs;
        _settings = settings;
        _ui = ui ?? new MemoryAppUiStore();
        var stored = _ui.Load();
        _isOpen = stored.AdvisorPanelOpen;
        _panelWidth = AppUiSettings.ClampAdvisorWidth(stored.AdvisorPanelWidth);
        _sessionKey = settings.AdvisorSessionKey;
        Entries.CollectionChanged += (_, _) =>
        {
            OnPropertyChanged(nameof(ShowEmptyConversation));
            OnPropertyChanged(nameof(ShowHistory));
            NewConversationCommand.NotifyCanExecuteChanged();
        };
        programs.PropertyChanged += OnProgramsChanged;
        settings.PropertyChanged += OnSettingsChanged;
    }

    public ObservableCollection<AdvisorChatEntry> Entries { get; } = [];

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(SendCommand))]
    private string _question = "";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(StateText))]
    [NotifyCanExecuteChangedFor(nameof(SendCommand), nameof(NewConversationCommand))]
    private bool _isAnswering;

    /// <summary>Seitenleiste offen; gemerkt in app-ui.json.</summary>
    [ObservableProperty]
    private bool _isOpen;

    /// <summary>Breite der Seitenleiste in Pixeln; gemerkt in app-ui.json.</summary>
    [ObservableProperty]
    private double _panelWidth;

    /// <summary>Gespeichert eingeschaltet und in dieser App verfügbar.</summary>
    public bool IsActive => _service is not null && _settings.IsAdvisorActive;

    public bool HasScan => _programs.LastScan is not null;

    public bool ShowDisabledState => !IsActive;

    public bool ShowNoScanState => IsActive && !HasScan;

    public bool ShowEmptyConversation => IsActive && HasScan && Entries.Count == 0;

    public bool CanType => IsActive && HasScan;

    public bool ShowHistory => CanType && Entries.Count > 0;

    /// <summary>Zeile über dem Eingabefeld: Antwort läuft, oder Scan bzw. Aktion läuft gerade.</summary>
    public string? StateText =>
        IsAnswering ? AppText.Get("AdvisorChatAnswering")
        : CanType && _programs.IsBusy ? AppText.Get("AdvisorChatWaitForWork")
        : null;

    /// <summary>Der Link „Einstellungen öffnen“ im leeren Zustand; das Hauptfenster wechselt die Seite.</summary>
    public event EventHandler? OpenSettingsRequested;

    [RelayCommand]
    private void Toggle() => IsOpen = !IsOpen;

    [RelayCommand]
    private void OpenSettings() => OpenSettingsRequested?.Invoke(this, EventArgs.Empty);

    private bool CanSend() => CanType && !_programs.IsBusy && !IsAnswering && !string.IsNullOrWhiteSpace(Question);

    /// <summary>
    /// Stellt die Frage. Bei Fehler oder Abbruch bleibt das Gespräch wie vor der Frage, und die Frage steht
    /// wieder im Eingabefeld.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanSend), IncludeCancelCommand = true)]
    private async Task SendAsync(CancellationToken cancellationToken)
    {
        var question = Question.Trim();
        Question = "";
        Entries.Add(new AdvisorChatEntry(AdvisorChatEntryKind.User, question));
        IsAnswering = true;
        _programs.IsAdvisorBusy = true;
        try
        {
            _session ??= await _service!.StartSessionAsync(cancellationToken);
            var reply = await _session.AskAsync(question, cancellationToken);
            var text = AdvisorPlainText.From(reply.Text);
            Entries.Add(new AdvisorChatEntry(AdvisorChatEntryKind.Assistant,
                text.Length == 0 ? AppText.Get("AdvisorChatEmptyAnswer") : text, ToolSummary(reply.ToolNames)));
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            Entries.Add(new AdvisorChatEntry(AdvisorChatEntryKind.Info, AppText.Get("AdvisorChatCancelled")));
            RestoreQuestion(question);
        }
        catch (AdvisorException ex)
        {
            Entries.Add(new AdvisorChatEntry(AdvisorChatEntryKind.Error, ex.Message));
            RestoreQuestion(question);
        }
        catch (Exception ex)
        {
            Entries.Add(new AdvisorChatEntry(AdvisorChatEntryKind.Error, AppText.Format("AdvisorChatFailed", ex.Message)));
            RestoreQuestion(question);
        }
        finally
        {
            IsAnswering = false;
            _programs.IsAdvisorBusy = false;
            if (_resetAfterAnswer)
            {
                _resetAfterAnswer = false;
                Reset(AppText.Get("AdvisorChatSettingsChanged"));
            }
        }
    }

    private bool CanStartNew() => !IsAnswering && (Entries.Count > 0 || _session is not null);

    [RelayCommand(CanExecute = nameof(CanStartNew))]
    private void NewConversation() => Reset(null);

    /// <summary>„Abgefragt: Programmliste, Programmdetails (2)“ in der Reihenfolge der Aufrufe.</summary>
    public static string ToolSummary(IReadOnlyList<string> toolNames)
    {
        if (toolNames.Count == 0)
        {
            return AppText.Get("AdvisorChatNoTools");
        }
        var parts = toolNames
            .GroupBy(n => n)
            .Select(g => (Label: AppText.Find("AdvisorChatTool_" + g.Key) ?? g.Key, Count: g.Count()))
            .Select(p => p.Count > 1 ? AppText.Format("AdvisorChatToolCount", p.Label, p.Count) : p.Label);
        return AppText.Format("AdvisorChatTools", string.Join(", ", parts));
    }

    private void RestoreQuestion(string question)
    {
        if (string.IsNullOrWhiteSpace(Question))
        {
            Question = question;
        }
    }

    /// <summary>Gespräch verwerfen; der Anbieter wird freigegeben. Mit Hinweis, wenn es einen Grund gibt.</summary>
    private void Reset(string? notice)
    {
        _session?.Dispose();
        _session = null;
        Entries.Clear();
        if (notice is not null)
        {
            Entries.Add(new AdvisorChatEntry(AdvisorChatEntryKind.Info, notice));
        }
        NewConversationCommand.NotifyCanExecuteChanged();
    }

    partial void OnIsOpenChanged(bool value) => _ui.Save(_ui.Load() with { AdvisorPanelOpen = value });

    partial void OnPanelWidthChanged(double value) => _ui.Save(_ui.Load() with { AdvisorPanelWidth = AppUiSettings.ClampAdvisorWidth(value) });

    private void OnProgramsChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(MainViewModel.IsBusy) or nameof(MainViewModel.LastScan))
        {
            NotifyState();
        }
    }

    private void OnSettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SettingsViewModel.IsAdvisorActive))
        {
            NotifyState();
        }
        if (e.PropertyName != nameof(SettingsViewModel.AdvisorSessionKey))
        {
            return;
        }
        var key = _settings.AdvisorSessionKey;
        if (key == _sessionKey)
        {
            return;
        }
        _sessionKey = key;
        // Anderes Modell, andere Adresse oder Stufe: Das alte Gespräch passt nicht mehr dazu.
        if (IsAnswering)
        {
            _resetAfterAnswer = true;
            SendCancelCommand.Execute(null);
        }
        else if (Entries.Count > 0 || _session is not null)
        {
            Reset(AppText.Get("AdvisorChatSettingsChanged"));
        }
        NotifyState();
    }

    private void NotifyState()
    {
        OnPropertyChanged(nameof(IsActive));
        OnPropertyChanged(nameof(HasScan));
        OnPropertyChanged(nameof(ShowDisabledState));
        OnPropertyChanged(nameof(ShowNoScanState));
        OnPropertyChanged(nameof(ShowEmptyConversation));
        OnPropertyChanged(nameof(CanType));
        OnPropertyChanged(nameof(ShowHistory));
        OnPropertyChanged(nameof(StateText));
        SendCommand.NotifyCanExecuteChanged();
    }
}
