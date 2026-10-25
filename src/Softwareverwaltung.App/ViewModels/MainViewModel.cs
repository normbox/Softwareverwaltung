using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows.Data;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;

namespace Softwareverwaltung.App.ViewModels;

public sealed partial class MainViewModel : ObservableObject
{
    private readonly IInventoryService _inventory;
    private readonly TimeProvider _time;
    private bool _initialized;
    private bool _ready;

    public MainViewModel(IInventoryService inventory, TimeProvider? time = null)
    {
        _inventory = inventory;
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
    [NotifyCanExecuteChangedFor(nameof(ScanCommand))]
    private bool _isBusy;

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
        if (_initialized)
        {
            return;
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
                AddNotice(new Notice(NoticeSeverity.Warning, "winget nicht verfügbar", winget.Message ?? "winget ist nicht verfügbar.",
                    winget.InstallUrl is null ? null : "App Installer im Microsoft Store", winget.InstallUrl), permanent: true);
            }
        }
        catch (Exception ex)
        {
            AddNotice(new Notice(NoticeSeverity.Error, "Start fehlgeschlagen", ex.Message), permanent: true);
            StatusText = "Die Module konnten nicht geladen werden.";
            IsBusy = false;
            return;
        }
        _ready = true;
        IsBusy = false;
        await ScanAsync(CancellationToken.None);
    }

    [RelayCommand(CanExecute = nameof(CanScan), IncludeCancelCommand = true)]
    private async Task ScanAsync(CancellationToken cancellationToken)
    {
        IsBusy = true;
        StatusText = "Scanne installierte Programme …";
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
