using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Softwareverwaltung.App.Localization;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;

namespace Softwareverwaltung.App.ViewModels;

/// <summary>
/// Seite „Sicherungen“: zeigt die Registry-Sicherungen von „Eintrag entfernen“ und bietet Löschen und
/// Zurückspielen an. Keine Fachlogik: Liste, Prüfung und Aktionen kommen vom Modul; zurückgespielt und gelöscht
/// wird erst nach der Bestätigung (Standard „Abbrechen“), auf demselben Weg wie die Aktionen der Programmliste.
/// </summary>
public sealed partial class BackupsViewModel : ObservableObject
{
    private readonly IBackupService _backups;
    private readonly IActionService _actions;
    private readonly IConfirmationService _confirmation;

    public BackupsViewModel(IBackupService backups, IActionService actions, IConfirmationService confirmation)
    {
        _backups = backups;
        _actions = actions;
        _confirmation = confirmation;
    }

    public ObservableCollection<RegistryBackupItem> Items { get; } = [];

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(RestoreCommand), nameof(DeleteCommand))]
    private RegistryBackupItem? _selectedItem;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(RestoreCommand), nameof(DeleteCommand), nameof(LoadCommand))]
    private bool _isBusy;

    [ObservableProperty]
    private string _statusText = "";

    /// <summary>Ergebnis der letzten Aktion, bis es geschlossen wird.</summary>
    [ObservableProperty]
    private ActionOutcome? _lastOutcome;

    public bool ShowEmptyHint => !IsBusy && Items.Count == 0;

    partial void OnIsBusyChanged(bool value) => OnPropertyChanged(nameof(ShowEmptyHint));

    /// <summary>Liste neu einlesen (beim Öffnen der Seite und mit „Aktualisieren“).</summary>
    [RelayCommand(CanExecute = nameof(CanLoad))]
    public async Task LoadAsync()
    {
        IsBusy = true;
        try
        {
            await ReloadAsync();
        }
        finally
        {
            IsBusy = false;
        }
    }

    private bool CanLoad() => !IsBusy;

    [RelayCommand(CanExecute = nameof(CanRestore))]
    private Task RestoreAsync() => RunAsync(SoftwareActionKind.RestoreBackup);

    [RelayCommand(CanExecute = nameof(CanDelete))]
    private Task DeleteAsync() => RunAsync(SoftwareActionKind.RemoveBackup);

    [RelayCommand]
    private void DismissOutcome() => LastOutcome = null;

    private bool CanRestore() => !IsBusy && SelectedItem is { CanRestore: true, Source: not null };

    private bool CanDelete() => !IsBusy && SelectedItem is { Source: not null };

    /// <summary>Plan holen, Bestätigung zeigen, genau diesen Plan ausführen, danach die Liste neu lesen.</summary>
    private async Task RunAsync(SoftwareActionKind kind)
    {
        var item = SelectedItem;
        if (item?.Source is null)
        {
            return;
        }
        IsBusy = true;
        StatusText = AppText.Get("StatusPlanning");
        try
        {
            var plan = await _actions.PlanAsync(kind, item.Source);
            if (!plan.IsPlanned)
            {
                LastOutcome = plan;
                StatusText = AppText.Format("StatusActionResult", plan.ActionText, plan.ResultText);
                return;
            }
            if (!_confirmation.Confirm(plan))
            {
                StatusText = AppText.Get("StatusActionCancelled");
                return;
            }
            StatusText = AppText.Format("StatusActionRunning", plan.ActionText, plan.Name);
            var outcome = await _actions.ExecuteAsync(kind, item.Source, plan);
            LastOutcome = outcome;
            StatusText = AppText.Format("StatusActionResult", outcome.ActionText, outcome.ResultText);
            await ReloadAsync(keepStatus: true);
        }
        catch (Exception ex)
        {
            LastOutcome = new ActionOutcome { Action = kind.ToString(), Name = item.Name, Result = "Failed", Message = ex.Message };
            StatusText = AppText.Get("StatusActionFailed");
        }
        finally
        {
            IsBusy = false;
        }
    }

    private async Task ReloadAsync(bool keepStatus = false)
    {
        try
        {
            var list = await _backups.GetBackupsAsync();
            var selectedId = SelectedItem?.Id;
            Items.Clear();
            foreach (var backup in list)
            {
                Items.Add(backup);
            }
            SelectedItem = Items.FirstOrDefault(i => i.Id == selectedId);
            if (!keepStatus)
            {
                StatusText = Items.Count == 0 ? "" : AppText.Format("BackupsCount", Items.Count);
            }
        }
        catch (Exception ex)
        {
            StatusText = AppText.Format("BackupsLoadFailed", ex.Message);
        }
        OnPropertyChanged(nameof(ShowEmptyHint));
    }
}
