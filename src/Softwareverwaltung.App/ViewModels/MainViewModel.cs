using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows.Data;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Softwareverwaltung.App.Localization;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;

namespace Softwareverwaltung.App.ViewModels;

public sealed partial class MainViewModel : ObservableObject
{
    private readonly IInventoryService _inventory;
    private readonly IActionService? _actions;
    private readonly IConfirmationService? _confirmation;
    private readonly IShellService? _shell;
    private readonly ICpeService? _cpe;
    private readonly TimeProvider _time;
    // Installationsordner je Programm, für die Sitzung gemerkt (ermittelt erst beim Aufklappen).
    private readonly Dictionary<string, InstallLocationInfo> _locations = [];
    // Warteschlange: Steuerung (State/Status) wird zwischen App und Modul geteilt.
    private System.Collections.Hashtable? _queueControl;
    private bool _initialized;
    private bool _ready;
    private Notice? _wingetNotice;

    public MainViewModel(IInventoryService inventory, IActionService? actions = null, IConfirmationService? confirmation = null, TimeProvider? time = null, IShellService? shell = null, ICpeService? cpe = null)
    {
        _inventory = inventory;
        _actions = actions;
        _confirmation = confirmation;
        _shell = shell;
        _cpe = cpe;
        _time = time ?? TimeProvider.System;
        ItemsView = new ListCollectionView(Items) { Filter = Matches };
        Items.CollectionChanged += (_, e) =>
        {
            foreach (var item in e.NewItems?.OfType<SoftwareItem>() ?? [])
            {
                item.Queue.PropertyChanged += (_, _) => OnQueueSelectionChanged();
            }
            OnQueueSelectionChanged();
        };
        ItemsView.SortDescriptions.Add(new SortDescription(nameof(SoftwareItem.Rating), ListSortDirection.Ascending));
        ItemsView.SortDescriptions.Add(new SortDescription(nameof(SoftwareItem.Name), ListSortDirection.Ascending));
    }

    public ObservableCollection<SoftwareItem> Items { get; } = [];

    public ListCollectionView ItemsView { get; }

    /// <summary>Dauerhafte Hinweise (z. B. winget fehlt) und Meldungen des letzten Scans.</summary>
    public ObservableCollection<Notice> Notices { get; } = [];

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(ScanCommand), nameof(UpdateCommand), nameof(UninstallCommand), nameof(RecheckWithoutCacheCommand), nameof(RetryWithNextMethodCommand), nameof(InstallWingetCommand), nameof(UpdateSelectedCommand), nameof(MapCpeCommand), nameof(ReportCpeCommand))]
    private bool _isBusy;

    /// <summary>Angeklicktes Programm; seine früheren Aktionen stehen in <see cref="History"/>.</summary>
    [ObservableProperty]
    private SoftwareItem? _selectedItem;

    public ObservableCollection<ActionHistoryEntry> History { get; } = [];

    /// <summary>Einträge der laufenden oder zuletzt gelaufenen Warteschlange mit Status.</summary>
    public ObservableCollection<QueueEntryState> QueueEntries { get; } = [];

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(PauseQueueCommand), nameof(ResumeQueueCommand), nameof(CancelQueueCommand))]
    private bool _queueRunning;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(PauseQueueCommand), nameof(ResumeQueueCommand))]
    private bool _queuePaused;

    public int QueueSelectedCount => Items.Count(i => i.Queue.IsChecked);

    public string QueueSelectionText => AppText.Format("QueueSelectionCount", QueueSelectedCount);

    public string QueueProgressText => AppText.Format("QueueProgress", QueueEntries.Count(e => e.IsDone), QueueEntries.Count);

    /// <summary>Wird ausgelöst, wenn die Warteschlange fertig ist (z. B. um die App danach zu schließen).</summary>
    public event EventHandler? QueueFinished;

    /// <summary>Installationsordner des angeklickten Programms; null, solange er ermittelt wird.</summary>
    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(OpenFolderCommand), nameof(CopyPathCommand))]
    private InstallLocationInfo? _selectedLocation;

    /// <summary>Ergebnis der letzten Aktion, als Karte oben angezeigt, bis der Benutzer sie schließt.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanRetryWithNextMethod))]
    [NotifyCanExecuteChangedFor(nameof(RetryWithNextMethodCommand))]
    private ActionOutcome? _lastOutcome;

    private SoftwareItem? _lastOutcomeItem;

    public bool CanRetryWithNextMethod => LastOutcome is { Action: "Uninstall", NextMethod: not null, IsSuccess: false } && _lastOutcomeItem is not null;

    public bool ActionsAvailable => _actions is not null && _confirmation is not null;

    [ObservableProperty]
    private string _statusText = AppText.Get("StatusReady");

    [ObservableProperty]
    private string _searchText = "";

    [ObservableProperty]
    private bool _showUpdatesOnly;

    [ObservableProperty]
    private bool _showRisksOnly;

    [ObservableProperty]
    private DateTimeOffset? _lastScan;

    public int VisibleCount => ItemsView.Count;

    public bool IsEmpty => Items.Count == 0;

    public bool ShowEmptyState => IsEmpty && !IsBusy;

    public string CountText => Items.Count == 0 ? "" :
        VisibleCount == Items.Count ? AppText.Format("CountAll", Items.Count) : AppText.Format("CountFiltered", VisibleCount, Items.Count);

    partial void OnIsBusyChanged(bool value) => OnPropertyChanged(nameof(ShowEmptyState));

    partial void OnSearchTextChanged(string value) => RefreshView();

    partial void OnShowUpdatesOnlyChanged(bool value) => RefreshView();

    partial void OnShowRisksOnlyChanged(bool value) => RefreshView();

    /// <summary>Lädt Module, prüft winget und startet den ersten Scan.</summary>
    public async Task InitializeAsync()
    {
        if (await LoadModulesAsync())
        {
            await ScanAsync(CancellationToken.None);
        }
    }

    /// <summary>Lädt Module und prüft winget, ohne zu scannen. Liefert false, wenn das Modul nicht bereit ist.</summary>
    public async Task<bool> LoadModulesAsync()
    {
        if (_initialized)
        {
            return _ready;
        }
        _initialized = true;
        IsBusy = true;
        StatusText = AppText.Get("StatusLoadingModules");
        try
        {
            foreach (var message in await _inventory.InitializeAsync())
            {
                AddNotice(new Notice(NoticeSeverity.Warning, AppText.Get("NoticeStartup"), message), permanent: true);
            }
            var winget = await _inventory.GetWingetStatusAsync();
            if (!winget.Available)
            {
                _wingetNotice = new Notice(NoticeSeverity.Warning, AppText.Get("NoticeWingetMissing"), winget.Message ?? AppText.Get("NoticeWingetMissingText"),
                    winget.InstallUrl is null ? null : AppText.Get("NoticeWingetStoreLink"), winget.InstallUrl,
                    _actions is null ? null : AppText.Get("ActionInstallWinget"), _actions is null ? null : InstallWingetCommand);
                AddNotice(_wingetNotice, permanent: true);
            }
        }
        catch (Exception ex)
        {
            AddNotice(new Notice(NoticeSeverity.Error, AppText.Get("NoticeStartFailed"), ex.Message), permanent: true);
            StatusText = AppText.Get("StatusModulesFailed");
            IsBusy = false;
            return false;
        }
        _ready = true;
        IsBusy = false;
        ScanCommand.NotifyCanExecuteChanged();
        return true;
    }

    /// <summary>Schalter „Ohne Cache“: Solange er an ist, fragt „Scannen“ alle Dienste neu ab.</summary>
    [ObservableProperty]
    private bool _scanWithoutCache;

    private bool _confirmingRefresh;

    /// <summary>
    /// Beim Einschalten ein Hinweis: ohne NVD-Schlüssel (laut Modul) die Rückfrage mit geschätzter Dauer –
    /// abgelehnt, geht der Schalter wieder aus; mit Schlüssel nur die Hinweiszeile.
    /// </summary>
    partial void OnScanWithoutCacheChanged(bool value)
    {
        if (value && !_confirmingRefresh)
        {
            _ = ConfirmScanWithoutCacheAsync();
        }
    }

    private async Task ConfirmScanWithoutCacheAsync()
    {
        var sources = Items.Select(i => i.Source).OfType<System.Management.Automation.PSObject>().ToList();
        if (_confirmation is null || sources.Count == 0)
        {
            return;
        }
        _confirmingRefresh = true;
        try
        {
            RefreshEstimate estimate;
            try
            {
                estimate = await _inventory.GetRefreshEstimateAsync(sources) ?? new RefreshEstimate(0, 0, NeedsConfirmation: false);
            }
            catch (Exception)
            {
                // Ohne Schätzung lieber nachfragen als still lange laufen.
                estimate = new RefreshEstimate(0, 0, NeedsConfirmation: true);
            }
            if (estimate.NeedsConfirmation && !await _confirmation.ConfirmRefreshAsync(estimate))
            {
                ScanWithoutCache = false;
            }
        }
        finally
        {
            _confirmingRefresh = false;
        }
    }

    [RelayCommand(CanExecute = nameof(CanScan), IncludeCancelCommand = true)]
    private async Task ScanAsync(CancellationToken cancellationToken)
    {
        var refresh = ScanWithoutCache;
        IsBusy = true;
        StatusText = AppText.Get("ScanRunning");
        ClearScanNotices();
        var progress = new Progress<string>(message => StatusText = message);
        try
        {
            var result = await _inventory.ScanAsync(progress, cancellationToken, refresh);
            Items.Clear();
            foreach (var item in result.Items)
            {
                Items.Add(item);
            }
            foreach (var warning in result.Warnings)
            {
                AddNotice(new Notice(NoticeSeverity.Warning, AppText.Get("NoticeHint"), warning), permanent: false);
            }
            foreach (var error in result.Errors)
            {
                AddNotice(new Notice(NoticeSeverity.Error, AppText.Get("NoticeScanError"), error), permanent: false);
            }
            LastScan = _time.GetLocalNow();
            StatusText = AppText.Format("StatusLastScan", LastScan);
        }
        catch (OperationCanceledException)
        {
            StatusText = AppText.Get("StatusScanCancelled");
        }
        catch (Exception ex)
        {
            AddNotice(new Notice(NoticeSeverity.Error, AppText.Get("NoticeScanError"), ex.Message), permanent: false);
            StatusText = AppText.Get("StatusScanFailed");
        }
        finally
        {
            IsBusy = false;
            RefreshView();
        }
    }

    private bool CanScan() => !IsBusy && _ready;

    /// <summary>Details: dieses Programm ohne Zwischenspeicher neu prüfen (auch den KEV-Katalog).</summary>
    [RelayCommand(CanExecute = nameof(CanRunAction))]
    private async Task RecheckWithoutCacheAsync(SoftwareItem? item)
    {
        IsBusy = true;
        StatusText = AppText.Get("StatusRechecking");
        try
        {
            await RecheckAsync(item!, refresh: true);
            StatusText = AppText.Get("StatusRecheckDone");
        }
        finally
        {
            IsBusy = false;
            RefreshView();
        }
    }

    private bool CanRunAction(SoftwareItem? item) => !IsBusy && _ready && ActionsAvailable && item?.Source is not null;

    [RelayCommand(CanExecute = nameof(CanRunAction))]
    private Task UpdateAsync(SoftwareItem? item) => RunActionAsync(SoftwareActionKind.Update, item, "Auto");

    [RelayCommand(CanExecute = nameof(CanRunAction))]
    private Task UninstallAsync(SoftwareItem? item) => RunActionAsync(SoftwareActionKind.Uninstall, item, "Auto");

    /// <summary>Nach einem Fehlschlag: nächste Methode, wieder mit eigener Bestätigung (kein automatischer Ersatzweg).</summary>
    [RelayCommand(CanExecute = nameof(CanRetry))]
    private Task RetryWithNextMethodAsync() => RunActionAsync(SoftwareActionKind.Uninstall, _lastOutcomeItem, LastOutcome!.NextMethod!);

    private bool CanRetry() => !IsBusy && CanRetryWithNextMethod;

    [RelayCommand(CanExecute = nameof(CanInstallWinget))]
    private Task InstallWingetAsync() => RunActionAsync(SoftwareActionKind.InstallWinget, null, "Auto");

    private bool CanInstallWinget() => !IsBusy && ActionsAvailable;

    [RelayCommand]
    private void DismissOutcome() => LastOutcome = null;

    private bool CanMapCpe(SoftwareItem? item) => !IsBusy && _ready && _cpe is not null && _confirmation is not null && item?.Source is not null && item.CanMapCpe;

    /// <summary>
    /// Details: „CPE zuordnen“. Vorschläge sind unbestätigt; gespeichert wird nur, was der Benutzer
    /// mit „Zuordnen“ bestätigt. Danach wird nur dieses Programm neu geprüft.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanMapCpe))]
    private async Task MapCpeAsync(SoftwareItem? item)
    {
        var dialog = new CpeMappingViewModel(item!, _cpe!);
        // Suche läuft, während das Fenster offen ist; Fehler zeigt das Fenster selbst als Hinweis.
        _ = dialog.SearchAsync();
        var choice = _confirmation!.ChooseCpe(dialog);
        if (choice is null)
        {
            StatusText = AppText.Get("StatusCpeCancelled");
            return;
        }
        IsBusy = true;
        try
        {
            if (choice.Remove)
            {
                await _cpe!.RemoveMappingAsync(item!.Source!);
                StatusText = AppText.Format("StatusCpeRemoved", item.Name);
            }
            else
            {
                await _cpe!.SetMappingAsync(item!.Source!, choice.Cpe!);
                StatusText = AppText.Format("StatusCpeAssigned", item.Name, choice.Cpe!);
            }
            await RecheckAsync(item);
        }
        catch (Exception ex)
        {
            AddNotice(new Notice(NoticeSeverity.Warning, AppText.Get("NoticeCpeFailed"), $"{item!.Name}: {ex.Message}"), permanent: false);
            StatusText = AppText.Get("NoticeCpeFailed");
        }
        finally
        {
            IsBusy = false;
            RefreshView();
        }
    }

    private bool CanReportCpe(SoftwareItem? item) => !IsBusy && _ready && _cpe is not null && _confirmation is not null && _shell is not null && item?.Source is not null && item.HasUserCpe;

    /// <summary>
    /// „Vorschlag melden“: zeigt den Inhalt des vorbereiteten GitHub-Issues und öffnet es erst nach
    /// Bestätigung im Browser. Abgeschickt wird es nur vom Benutzer selbst.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanReportCpe))]
    private async Task ReportCpeAsync(SoftwareItem? item)
    {
        try
        {
            var report = await _cpe!.GetReportAsync(item!.Source!);
            if (await _confirmation!.ConfirmCpeReportAsync(report))
            {
                _shell!.OpenUrl(report.Url);
                StatusText = AppText.Get("StatusCpeReportOpened");
            }
        }
        catch (Exception ex)
        {
            AddNotice(new Notice(NoticeSeverity.Warning, AppText.Get("NoticeCpeReportFailed"), $"{item!.Name}: {ex.Message}"), permanent: false);
        }
    }

    partial void OnSelectedItemChanged(SoftwareItem? value)
    {
        _ = LoadHistoryAsync(value);
        _ = LoadLocationAsync(value);
    }

    private void OnQueueSelectionChanged()
    {
        OnPropertyChanged(nameof(QueueSelectedCount));
        OnPropertyChanged(nameof(QueueSelectionText));
        UpdateSelectedCommand.NotifyCanExecuteChanged();
    }

    /// <summary>Alle Programme mit verfügbarem Update für die Warteschlange auswählen (auch unbestätigte).</summary>
    [RelayCommand]
    private void SelectAllWithUpdate()
    {
        foreach (var item in Items.Where(i => i.UpdateAvailable))
        {
            item.Queue.IsChecked = true;
        }
    }

    [RelayCommand]
    private void ClearQueueSelection()
    {
        foreach (var item in Items)
        {
            item.Queue.IsChecked = false;
        }
    }

    private bool CanUpdateSelected() => !IsBusy && _ready && ActionsAvailable && QueueSelectedCount > 0;

    /// <summary>
    /// Update-Warteschlange (nur Updates; Deinstallieren bleibt einzeln): planen, gemeinsam bestätigen,
    /// ausführen mit Fortschritt je Eintrag, danach nur die betroffenen Programme neu prüfen.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanUpdateSelected))]
    private async Task UpdateSelectedAsync()
    {
        var selected = Items.Where(i => i.Queue.IsChecked && i.Source is not null).ToList();
        IsBusy = true;
        StatusText = AppText.Get("StatusQueuePlanning");
        try
        {
            var planProgress = new Progress<string>(message => StatusText = message);
            var plan = await _actions!.PlanUpdateQueueAsync(selected.Select(i => i.Source!).ToList(), planProgress);
            // Store-Pakete in der Auswahl: einmal die Store-Vereinbarung bestätigen lassen, dann neu planen.
            if (plan.Any(e => e.Result == "StoreAgreementRequired") && await EnsureStoreAgreementAsync())
            {
                plan = await _actions.PlanUpdateQueueAsync(selected.Select(i => i.Source!).ToList(), planProgress);
            }
            var confirmation = new QueueConfirmation(plan);
            if (!confirmation.CanStart || !_confirmation!.ConfirmQueue(confirmation))
            {
                StatusText = AppText.Get("StatusActionCancelled");
                return;
            }
            var entries = plan.Where(e => e.Executable).ToList();
            QueueEntries.Clear();
            foreach (var entry in entries)
            {
                QueueEntries.Add(new QueueEntryState(entry.Index, entry.Name));
            }
            _queueControl = System.Collections.Hashtable.Synchronized(new System.Collections.Hashtable { ["State"] = "Running" });
            QueuePaused = false;
            QueueRunning = true;
            var progress = new Progress<string>(message => StatusText = message);
            var run = _actions.RunUpdateQueueAsync(entries, _queueControl, progress);
            // Status je Eintrag aus der gemeinsamen Steuerung lesen, solange die Warteschlange läuft.
            while (!run.IsCompleted)
            {
                await Task.WhenAny(run, Task.Delay(400));
                RefreshQueueStatus();
            }
            var results = await run;
            RefreshQueueStatus();
            // Bei Fehlschlag den Grund am Eintrag zeigen (z. B. Netzwerkfehler), nicht nur im Protokoll.
            foreach (var entry in QueueEntries)
            {
                var result = results.FirstOrDefault(r => r.Name == entry.Name);
                entry.Message = result is { IsSuccess: false } ? result.Message : null;
            }
            StatusText = AppText.Format("StatusQueueDone", results.Count(r => r.IsSuccess), results.Count);

            // Nur betroffene Programme neu prüfen: was wirklich gelaufen ist (nicht abgebrochen, nicht übersprungen).
            var ran = results.Where(r => r.Result != "Cancelled").Select(r => r.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
            foreach (var item in selected.Where(i => ran.Contains(i.Name)))
            {
                try
                {
                    await _actions.ClearCheckCacheAsync(item.Source!);
                }
                catch (Exception)
                {
                    // Verwerfen ist eine Zusatzhilfe; die nächste Prüfung richtet sich dann nach der Haltbarkeit.
                }
                await RecheckAsync(item);
            }
            ClearQueueSelection();
        }
        catch (Exception ex)
        {
            AddNotice(new Notice(NoticeSeverity.Error, AppText.Get("NoticeQueueFailed"), ex.Message), permanent: false);
            StatusText = AppText.Get("StatusActionFailed");
        }
        finally
        {
            QueueRunning = false;
            QueuePaused = false;
            _queueControl = null;
            IsBusy = false;
            RefreshView();
            QueueFinished?.Invoke(this, EventArgs.Empty);
        }
    }

    /// <summary>
    /// Zeigt die Vereinbarung der Quelle „msstore“ (Standard „Abbrechen“) und speichert die Zustimmung.
    /// Ohne Zustimmung bleibt der Eintrag nicht ausführbar, mit Grund.
    /// </summary>
    private async Task<bool> EnsureStoreAgreementAsync()
    {
        var agreement = await _actions!.GetStoreAgreementAsync();
        if (!_confirmation!.ConfirmStoreAgreement(agreement))
        {
            return false;
        }
        await _actions.AcceptStoreAgreementAsync();
        return true;
    }

    private void RefreshQueueStatus()
    {
        if (_queueControl?["Status"] is not System.Collections.IDictionary status)
        {
            return;
        }
        foreach (var entry in QueueEntries)
        {
            if (status[entry.Index] is { } code)
            {
                entry.Status = code.ToString()!;
            }
        }
        OnPropertyChanged(nameof(QueueProgressText));
    }

    [RelayCommand(CanExecute = nameof(CanPauseQueue))]
    private void PauseQueue()
    {
        _queueControl!["State"] = "Paused";
        QueuePaused = true;
        StatusText = AppText.Get("StatusQueuePaused");
    }

    private bool CanPauseQueue() => QueueRunning && !QueuePaused;

    [RelayCommand(CanExecute = nameof(CanResumeQueue))]
    private void ResumeQueue()
    {
        _queueControl!["State"] = "Running";
        QueuePaused = false;
    }

    private bool CanResumeQueue() => QueueRunning && QueuePaused;

    /// <summary>Abbrechen: die laufende Aktion wird fertig, der Rest wird nicht ausgeführt (und protokolliert).</summary>
    [RelayCommand(CanExecute = nameof(QueueRunning))]
    public void CancelQueue()
    {
        if (_queueControl is not null)
        {
            _queueControl["State"] = "Cancelled";
        }
        QueuePaused = false;
        StatusText = AppText.Get("StatusQueueCancelling");
    }

    [RelayCommand]
    private void DismissQueue()
    {
        if (!QueueRunning)
        {
            QueueEntries.Clear();
        }
    }

    /// <summary>Klappt die Details zu (Button „Schließen“, Esc, zweiter Klick auf die Zeile).</summary>
    [RelayCommand]
    private void CloseDetails() => SelectedItem = null;

    [RelayCommand(CanExecute = nameof(CanOpenFolder))]
    private void OpenFolder() => _shell?.OpenFolder(SelectedLocation!.Path!);

    private bool CanOpenFolder() => _shell is not null && SelectedLocation is { IsKnown: true, CanOpen: true };

    [RelayCommand(CanExecute = nameof(CanCopyPath))]
    private void CopyPath()
    {
        _shell?.CopyText(SelectedLocation!.Path!);
        StatusText = AppText.Get("StatusPathCopied");
    }

    private bool CanCopyPath() => _shell is not null && SelectedLocation is { IsKnown: true };

    private async Task LoadLocationAsync(SoftwareItem? item)
    {
        SelectedLocation = null;
        if (item?.Source is null || IsBusy || !_ready)
        {
            return;
        }
        var key = LocationKey(item);
        if (!_locations.TryGetValue(key, out var location))
        {
            try
            {
                location = await _inventory.ResolveInstallLocationAsync(item.Source);
            }
            catch (Exception)
            {
                // Der Ordner ist eine Zusatzinfo; fehlt er, bleibt die Zeile leer.
                return;
            }
            if (location is null)
            {
                return;
            }
            _locations[key] = location;
        }
        if (SelectedItem == item)
        {
            SelectedLocation = location;
        }
    }

    // Gleiches Programm in gleicher Version: nach einem Update (neue Version) wird neu ermittelt.
    private static string LocationKey(SoftwareItem item) => $"{item.Name}|{item.InstalledVersion}|{item.Sources}|{item.InstallLocation}";

    /// <summary>
    /// Ablauf jeder Aktion: Plan mit -WhatIf holen, Bestätigung zeigen, genau diesen Befehl ausführen,
    /// danach nur dieses Programm neu prüfen. Nicht ausführbare Pläne (z. B. Update von Hand) kommen
    /// ohne Dialog direkt als Ergebnis.
    /// </summary>
    private async Task RunActionAsync(SoftwareActionKind kind, SoftwareItem? item, string method)
    {
        if (_actions is null || _confirmation is null)
        {
            return;
        }
        IsBusy = true;
        StatusText = AppText.Get("StatusPlanning");
        try
        {
            var plan = await _actions.PlanAsync(kind, item?.Source, method);
            // Store-Paket: erst die Store-Vereinbarung bestätigen lassen, dann neu planen.
            if (plan.IsStoreAgreementRequired && await EnsureStoreAgreementAsync())
            {
                plan = await _actions.PlanAsync(kind, item?.Source, method);
            }
            if (!plan.IsPlanned)
            {
                ShowOutcome(plan, item);
                StatusText = AppText.Format("StatusActionResult", plan.ActionText, plan.ResultText);
                return;
            }
            if (!_confirmation.Confirm(plan))
            {
                StatusText = AppText.Get("StatusActionCancelled");
                return;
            }

            StatusText = AppText.Format("StatusActionRunning", plan.ActionText, plan.Name) + (plan.Elevated ? " " + AppText.Get("StatusConfirmUac") : "");
            var outcome = await _actions.ExecuteAsync(kind, item?.Source, plan, method);
            StatusText = AppText.Format("StatusActionResult", outcome.ActionText, outcome.ResultText);

            if (kind == SoftwareActionKind.InstallWinget)
            {
                ShowOutcome(outcome, null);
                if (outcome.IsSuccess && _wingetNotice is not null)
                {
                    _permanentNotices.Remove(_wingetNotice);
                    Notices.Remove(_wingetNotice);
                    _wingetNotice = null;
                    StatusText += " " + AppText.Get("StatusRescanForWinget");
                }
                return;
            }
            // Online-Ergebnisse dieses Programms verwerfen, dann neu prüfen.
            try
            {
                await _actions.ClearCheckCacheAsync(item!.Source!);
            }
            catch (Exception)
            {
                // Verwerfen ist eine Zusatzhilfe; schlägt es fehl, prüft die nächste Abfrage nach Haltbarkeit.
            }
            ShowOutcome(outcome, await RecheckAsync(item!));
        }
        catch (Exception ex)
        {
            ShowOutcome(new ActionOutcome { Action = kind.ToString(), Name = item?.Name ?? "winget", Result = "Failed", Message = ex.Message }, item);
            StatusText = AppText.Get("StatusActionFailed");
        }
        finally
        {
            IsBusy = false;
            RefreshView();
        }
        await LoadHistoryAsync(SelectedItem);
        await LoadLocationAsync(SelectedItem);
    }

    private void ShowOutcome(ActionOutcome outcome, SoftwareItem? item)
    {
        _lastOutcomeItem = item;
        LastOutcome = outcome;
        OnPropertyChanged(nameof(CanRetryWithNextMethod));
        RetryWithNextMethodCommand.NotifyCanExecuteChanged();
    }

    /// <summary>Liest nur dieses Programm neu ein: Zeile ersetzen oder entfernen, wenn es weg ist.</summary>
    private async Task<SoftwareItem?> RecheckAsync(SoftwareItem item, bool refresh = false)
    {
        var statusBefore = StatusText;
        StatusText += " " + AppText.Get("StatusRechecking");
        SoftwareItem? updated;
        try
        {
            updated = await _actions!.RecheckAsync(item.Source!, refresh: refresh);
        }
        catch (Exception ex)
        {
            AddNotice(new Notice(NoticeSeverity.Warning, AppText.Get("NoticeRecheckFailed"), $"{item.Name}: {ex.Message}"), permanent: false);
            return item;
        }
        var index = Items.IndexOf(item);
        if (updated is null)
        {
            if (index >= 0)
            {
                Items.RemoveAt(index);
            }
            StatusText = statusBefore + " " + AppText.Get("StatusProgramGone");
            return null;
        }
        if (index >= 0)
        {
            Items[index] = updated;
        }
        if (SelectedItem == item)
        {
            SelectedItem = updated;
        }
        StatusText = statusBefore;
        return updated;
    }

    private async Task LoadHistoryAsync(SoftwareItem? item)
    {
        History.Clear();
        if (item is null || _actions is null || IsBusy)
        {
            return;
        }
        try
        {
            foreach (var entry in await _actions.GetHistoryAsync(item.Name))
            {
                if (SelectedItem == item)
                {
                    History.Add(entry);
                }
            }
        }
        catch (Exception)
        {
            // Der Verlauf ist eine Zusatzinfo; fehlt er, bleibt die Liste leer.
        }
    }

    [RelayCommand]
    private void DismissNotice(Notice notice) => Notices.Remove(notice);

    private readonly HashSet<Notice> _permanentNotices = [];

    private void AddNotice(Notice notice, bool permanent)
    {
        if (permanent)
        {
            _permanentNotices.Add(notice);
        }
        Notices.Add(notice);
    }

    private void ClearScanNotices()
    {
        foreach (var notice in Notices.Where(n => !_permanentNotices.Contains(n)).ToList())
        {
            Notices.Remove(notice);
        }
    }

    private bool Matches(object obj)
    {
        if (obj is not SoftwareItem item)
        {
            return false;
        }
        if (ShowUpdatesOnly && !item.UpdateAvailable)
        {
            return false;
        }
        if (ShowRisksOnly && !item.HasSecurityRisk)
        {
            return false;
        }
        var search = SearchText.Trim();
        return search.Length == 0
            || item.Name.Contains(search, StringComparison.CurrentCultureIgnoreCase)
            || (item.Publisher?.Contains(search, StringComparison.CurrentCultureIgnoreCase) ?? false);
    }

    private void RefreshView()
    {
        ItemsView.Refresh();
        OnPropertyChanged(nameof(VisibleCount));
        OnPropertyChanged(nameof(CountText));
        OnPropertyChanged(nameof(IsEmpty));
        OnPropertyChanged(nameof(ShowEmptyState));
    }
}
