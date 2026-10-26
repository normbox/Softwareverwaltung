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
    private readonly TimeProvider _time;
    private bool _initialized;
    private bool _ready;
    private Notice? _wingetNotice;

    public MainViewModel(IInventoryService inventory, IActionService? actions = null, IConfirmationService? confirmation = null, TimeProvider? time = null)
    {
        _inventory = inventory;
        _actions = actions;
        _confirmation = confirmation;
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
    [NotifyCanExecuteChangedFor(nameof(ScanCommand), nameof(UpdateCommand), nameof(UninstallCommand), nameof(RetryWithNextMethodCommand), nameof(InstallWingetCommand))]
    private bool _isBusy;

    /// <summary>Angeklicktes Programm; seine früheren Aktionen stehen in <see cref="History"/>.</summary>
    [ObservableProperty]
    private SoftwareItem? _selectedItem;

    public ObservableCollection<ActionHistoryEntry> History { get; } = [];

    /// <summary>Ergebnis der letzten Aktion, als Karte oben angezeigt, bis der Benutzer sie schließt.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanRetryWithNextMethod))]
    [NotifyCanExecuteChangedFor(nameof(RetryWithNextMethodCommand))]
    private ActionOutcome? _lastOutcome;

    private SoftwareItem? _lastOutcomeItem;

    public bool CanRetryWithNextMethod => LastOutcome is { Action: "Uninstall", NextMethod: not null, IsSuccess: false } && _lastOutcomeItem is not null;

    public bool ActionsAvailable => _actions is not null && _confirmation is not null;

    [ObservableProperty]
    private string _statusText = "Bereit.";

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
        VisibleCount == Items.Count ? $"{Items.Count} Programme" : $"{VisibleCount} von {Items.Count} Programmen";

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
        StatusText = "Lade Module …";
        try
        {
            foreach (var message in await _inventory.InitializeAsync())
            {
                AddNotice(new Notice(NoticeSeverity.Warning, "Beim Start", message), permanent: true);
            }
            var winget = await _inventory.GetWingetStatusAsync();
            if (!winget.Available)
            {
                _wingetNotice = new Notice(NoticeSeverity.Warning, "winget nicht verfügbar", winget.Message ?? "winget ist nicht verfügbar.",
                    winget.InstallUrl is null ? null : "App Installer im Microsoft Store", winget.InstallUrl,
                    _actions is null ? null : "winget installieren", _actions is null ? null : InstallWingetCommand);
                AddNotice(_wingetNotice, permanent: true);
            }
        }
        catch (Exception ex)
        {
            AddNotice(new Notice(NoticeSeverity.Error, "Start fehlgeschlagen", ex.Message), permanent: true);
            StatusText = "Die Module konnten nicht geladen werden.";
            IsBusy = false;
            return false;
        }
        _ready = true;
        IsBusy = false;
        ScanCommand.NotifyCanExecuteChanged();
        return true;
    }

    [RelayCommand(CanExecute = nameof(CanScan), IncludeCancelCommand = true)]
    private async Task ScanAsync(CancellationToken cancellationToken)
    {
        IsBusy = true;
        StatusText = AppText.Get("ScanRunning");
        ClearScanNotices();
        var progress = new Progress<string>(message => StatusText = message);
        try
        {
            var result = await _inventory.ScanAsync(progress, cancellationToken);
            Items.Clear();
            foreach (var item in result.Items)
            {
                Items.Add(item);
            }
            foreach (var warning in result.Warnings)
            {
                AddNotice(new Notice(NoticeSeverity.Warning, "Hinweis", warning), permanent: false);
            }
            foreach (var error in result.Errors)
            {
                AddNotice(new Notice(NoticeSeverity.Error, "Fehler beim Scan", error), permanent: false);
            }
            LastScan = _time.GetLocalNow();
            StatusText = $"Zuletzt gescannt: {LastScan:dd.MM.yyyy HH:mm}";
        }
        catch (OperationCanceledException)
        {
            StatusText = "Scan abgebrochen.";
        }
        catch (Exception ex)
        {
            AddNotice(new Notice(NoticeSeverity.Error, "Fehler beim Scan", ex.Message), permanent: false);
            StatusText = "Scan fehlgeschlagen.";
        }
        finally
        {
            IsBusy = false;
            RefreshView();
        }
    }

    private bool CanScan() => !IsBusy && _ready;

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

    partial void OnSelectedItemChanged(SoftwareItem? value) => _ = LoadHistoryAsync(value);

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
        StatusText = "Prüfe, was ausgeführt würde …";
        try
        {
            var plan = await _actions.PlanAsync(kind, item?.Source, method);
            if (!plan.IsPlanned)
            {
                ShowOutcome(plan, item);
                StatusText = $"{plan.ActionText}: {plan.ResultText}";
                return;
            }
            if (!_confirmation.Confirm(plan))
            {
                StatusText = "Abgebrochen; es wurde nichts ausgeführt.";
                return;
            }

            StatusText = $"{plan.ActionText}: {plan.Name} läuft …" + (plan.Elevated ? " Bitte die Windows-Abfrage (UAC) bestätigen." : "");
            var outcome = await _actions.ExecuteAsync(kind, item?.Source, plan, method);
            StatusText = $"{outcome.ActionText}: {outcome.ResultText}";

            if (kind == SoftwareActionKind.InstallWinget)
            {
                ShowOutcome(outcome, null);
                if (outcome.IsSuccess && _wingetNotice is not null)
                {
                    _permanentNotices.Remove(_wingetNotice);
                    Notices.Remove(_wingetNotice);
                    _wingetNotice = null;
                    StatusText += " Ein neuer Scan übernimmt die winget-Daten.";
                }
                return;
            }
            ShowOutcome(outcome, await RecheckAsync(item!));
        }
        catch (Exception ex)
        {
            ShowOutcome(new ActionOutcome { Action = kind.ToString(), Name = item?.Name ?? "winget", Result = "Failed", Message = ex.Message }, item);
            StatusText = "Aktion fehlgeschlagen.";
        }
        finally
        {
            IsBusy = false;
            RefreshView();
        }
        await LoadHistoryAsync(SelectedItem);
    }

    private void ShowOutcome(ActionOutcome outcome, SoftwareItem? item)
    {
        _lastOutcomeItem = item;
        LastOutcome = outcome;
        OnPropertyChanged(nameof(CanRetryWithNextMethod));
        RetryWithNextMethodCommand.NotifyCanExecuteChanged();
    }

    /// <summary>Liest nur dieses Programm neu ein: Zeile ersetzen oder entfernen, wenn es weg ist.</summary>
    private async Task<SoftwareItem?> RecheckAsync(SoftwareItem item)
    {
        StatusText += " Prüfe das Programm neu …";
        SoftwareItem? updated;
        try
        {
            updated = await _actions!.RecheckAsync(item.Source!);
        }
        catch (Exception ex)
        {
            AddNotice(new Notice(NoticeSeverity.Warning, "Neu prüfen fehlgeschlagen", $"{item.Name}: {ex.Message}"), permanent: false);
            return item;
        }
        var index = Items.IndexOf(item);
        if (updated is null)
        {
            if (index >= 0)
            {
                Items.RemoveAt(index);
            }
            StatusText = StatusText.Replace(" Prüfe das Programm neu …", " Das Programm ist nicht mehr installiert.");
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
        StatusText = StatusText.Replace(" Prüfe das Programm neu …", "");
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
