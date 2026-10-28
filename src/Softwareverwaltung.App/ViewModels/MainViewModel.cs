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
    private readonly TimeProvider _time;
    // Installationsordner je Programm, für die Sitzung gemerkt (ermittelt erst beim Aufklappen).
    private readonly Dictionary<string, InstallLocationInfo> _locations = [];
    private bool _refreshNextScan;
    private bool _initialized;
    private bool _ready;
    private Notice? _wingetNotice;

    public MainViewModel(IInventoryService inventory, IActionService? actions = null, IConfirmationService? confirmation = null, TimeProvider? time = null, IShellService? shell = null)
    {
        _inventory = inventory;
        _actions = actions;
        _confirmation = confirmation;
        _shell = shell;
        _time = time ?? TimeProvider.System;
        ItemsView = new ListCollectionView(Items) { Filter = Matches };
        ItemsView.SortDescriptions.Add(new SortDescription(nameof(SoftwareItem.Rating), ListSortDirection.Ascending));
        ItemsView.SortDescriptions.Add(new SortDescription(nameof(SoftwareItem.Name), ListSortDirection.Ascending));
    }

    public ObservableCollection<SoftwareItem> Items { get; } = [];

    public ListCollectionView ItemsView { get; }

    /// <summary>Dauerhafte Hinweise (z. B. winget fehlt) und Meldungen des letzten Scans.</summary>
    public ObservableCollection<Notice> Notices { get; } = [];

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(ScanCommand), nameof(ScanWithoutCacheCommand), nameof(UpdateCommand), nameof(UninstallCommand), nameof(RecheckWithoutCacheCommand), nameof(RetryWithNextMethodCommand), nameof(InstallWingetCommand))]
    private bool _isBusy;

    /// <summary>Angeklicktes Programm; seine früheren Aktionen stehen in <see cref="History"/>.</summary>
    [ObservableProperty]
    private SoftwareItem? _selectedItem;

    public ObservableCollection<ActionHistoryEntry> History { get; } = [];

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
        ScanWithoutCacheCommand.NotifyCanExecuteChanged();
        return true;
    }

    /// <summary>
    /// Scan ohne Zwischenspeicher. Ohne NVD-Schlüssel (laut Modul) erst nachfragen, mit geschätzter Dauer;
    /// mit Schlüssel ohne Rückfrage. Abbrechen geht wie beim normalen Scan.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanScan))]
    private async Task ScanWithoutCacheAsync()
    {
        var sources = Items.Select(i => i.Source).OfType<System.Management.Automation.PSObject>().ToList();
        if (_confirmation is not null && sources.Count > 0)
        {
            RefreshEstimate? estimate = null;
            try
            {
                estimate = await _inventory.GetRefreshEstimateAsync(sources);
            }
            catch (Exception)
            {
                // Ohne Schätzung lieber nachfragen als still lange laufen.
                estimate = new RefreshEstimate(0, 0, NeedsConfirmation: true);
            }
            if (estimate is { NeedsConfirmation: true } && !await _confirmation.ConfirmRefreshAsync(estimate))
            {
                StatusText = AppText.Get("StatusRefreshNotStarted");
                return;
            }
        }
        _refreshNextScan = true;
        await ScanCommand.ExecuteAsync(null);
    }

    [RelayCommand(CanExecute = nameof(CanScan), IncludeCancelCommand = true)]
    private async Task ScanAsync(CancellationToken cancellationToken)
    {
        var refresh = _refreshNextScan;
        _refreshNextScan = false;
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

    partial void OnSelectedItemChanged(SoftwareItem? value)
    {
        _ = LoadHistoryAsync(value);
        _ = LoadLocationAsync(value);
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
