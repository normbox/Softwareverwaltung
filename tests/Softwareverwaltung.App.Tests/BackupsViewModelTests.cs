using System.Management.Automation;
using Softwareverwaltung.App.Localization;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;
using Softwareverwaltung.App.ViewModels;
using static Softwareverwaltung.App.Tests.TestHelpers;

namespace Softwareverwaltung.App.Tests;

/// <summary>Seite „Sicherungen“: Liste, Wiederherstellen und Löschen mit Bestätigung; keine Fachlogik in der App.</summary>
public sealed class BackupsViewModelTests
{
    private static PSObject Message(string code, string text) => Ps(("Code", code), ("Args", Array.Empty<object>()), ("Text", text));

    private static RegistryBackupItem Backup(string id, string name, bool canRestore = true, bool legacy = false) => RegistryBackupItem.FromPs(Ps(
        ("Id", id), ("Name", name), ("CreatedAt", new DateTime(2026, 11, 16, 12, 0, 0, DateTimeKind.Utc)),
        ("NativeKey", @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\" + name),
        ("IsLegacy", legacy), ("CanRestore", canRestore), ("Problem", canRestore ? null : "MetadataMissing"),
        ("ProblemMessage", canRestore ? null : Message("BackupMetadataMissing", "Ältere Sicherung ohne Begleitdatei")),
        ("Reasons", new object[] { Message("OrphanedEntry", "Programm nicht mehr vorhanden"), Message("NewerInstallNextTo", "Neuere Installation daneben: Jan 0.8.8") })));

    private static ActionOutcome Planned(string action, string id) => new() { Action = action, Name = "Jan", Result = "Planned", CommandLine = id, Message = "Beschreibung" };

    private static (BackupsViewModel Vm, FakeBackups Backups, FakeActions Actions, FakeConfirm Confirm) Create(bool confirm = true, params RegistryBackupItem[] items)
    {
        var backups = new FakeBackups { Items = items };
        var actions = new FakeActions();
        var confirmation = new FakeConfirm { Answer = confirm };
        return (new BackupsViewModel(backups, actions, confirmation), backups, actions, confirmation);
    }

    [Fact]
    public void ListShowsNameDateReasonsAndWhetherItCanBeRestored() => RunOnDispatcher(async () =>
    {
        var (vm, _, _, _) = Create(true, Backup("id-1", "Jan"), Backup("id-2", "Alt", canRestore: false, legacy: true));
        await vm.LoadAsync();

        Assert.Equal(2, vm.Items.Count);
        var jan = vm.Items[0];
        Assert.Equal("Jan", jan.Name);
        Assert.Contains("Programm nicht mehr vorhanden", jan.ReasonsText);
        Assert.Contains("Neuere Installation daneben: Jan 0.8.8", jan.ReasonsText);
        Assert.Equal(AppText.Get("BackupsRestorable"), jan.StatusText);
        Assert.NotEqual("", jan.WhenText);
        var legacy = vm.Items[1];
        Assert.Equal(AppText.Get("BackupsLegacyReason"), legacy.ReasonsText);
        Assert.Equal("Ältere Sicherung ohne Begleitdatei", legacy.StatusText);
        Assert.False(vm.ShowEmptyHint);
    });

    [Fact]
    public void WithoutBackupsAHintIsShown() => RunOnDispatcher(async () =>
    {
        var (vm, _, _, _) = Create();
        await vm.LoadAsync();
        Assert.True(vm.ShowEmptyHint);
        Assert.Equal("", vm.StatusText);
    });

    [Fact]
    public void LoadErrorsAreShownNotThrown() => RunOnDispatcher(async () =>
    {
        var (vm, backups, _, _) = Create();
        backups.Failure = new InvalidOperationException("kaputt");
        await vm.LoadAsync();
        Assert.Contains("kaputt", vm.StatusText);
        Assert.False(vm.IsBusy);
    });

    [Fact]
    public void RestoreOnlyForBackupsTheModuleCallsRestorable() => RunOnDispatcher(async () =>
    {
        var (vm, _, _, _) = Create(true, Backup("id-1", "Jan"), Backup("id-2", "Alt", canRestore: false, legacy: true));
        await vm.LoadAsync();

        vm.SelectedItem = vm.Items[0];
        Assert.True(vm.RestoreCommand.CanExecute(null));
        Assert.True(vm.DeleteCommand.CanExecute(null));
        vm.SelectedItem = vm.Items[1];
        Assert.False(vm.RestoreCommand.CanExecute(null));
        Assert.True(vm.DeleteCommand.CanExecute(null), "Ältere Sicherungen lassen sich löschen");
        vm.SelectedItem = null;
        Assert.False(vm.RestoreCommand.CanExecute(null));
        Assert.False(vm.DeleteCommand.CanExecute(null));
    });

    [Fact]
    public void RestorePlansConfirmsRunsExactlyTheConfirmedPlanAndReloadsTheList() => RunOnDispatcher(async () =>
    {
        var (vm, backups, actions, confirm) = Create(true, Backup("id-1", "Jan"));
        actions.Plan = Planned("RestoreBackup", "id-1");
        actions.Outcome = new ActionOutcome { Action = "RestoreBackup", Name = "Jan", Result = "Succeeded", Message = "Eintrag zurückgeschrieben" };
        await vm.LoadAsync();
        vm.SelectedItem = vm.Items[0];

        await vm.RestoreCommand.ExecuteAsync(null);

        Assert.Equal(["Plan:RestoreBackup", "Execute:RestoreBackup:id-1"], actions.Calls);
        Assert.Single(confirm.Shown);
        Assert.Equal("Succeeded", vm.LastOutcome?.Result);
        Assert.Equal(2, backups.Loads);
        Assert.False(vm.IsBusy);
    });

    [Fact]
    public void DeclinedConfirmationRunsNothing() => RunOnDispatcher(async () =>
    {
        var (vm, _, actions, confirm) = Create(false, Backup("id-1", "Jan"));
        actions.Plan = Planned("RemoveBackup", "id-1");
        await vm.LoadAsync();
        vm.SelectedItem = vm.Items[0];

        await vm.DeleteCommand.ExecuteAsync(null);

        Assert.Equal(["Plan:RemoveBackup"], actions.Calls);
        Assert.Single(confirm.Shown);
        Assert.Equal(AppText.Get("StatusActionCancelled"), vm.StatusText);
        Assert.Null(vm.LastOutcome);
    });

    [Fact]
    public void ARefusedPlanIsShownWithoutAConfirmationDialog() => RunOnDispatcher(async () =>
    {
        var (vm, _, actions, confirm) = Create(true, Backup("id-1", "Alt", canRestore: false, legacy: true));
        actions.Plan = new ActionOutcome { Action = "RestoreBackup", Name = "Alt", Result = "Unsupported", MessageCode = "BackupMetadataMissing", Message = "Ältere Sicherung ohne Begleitdatei" };
        await vm.LoadAsync();
        vm.SelectedItem = vm.Items[0];

        await vm.RestoreCommand.ExecuteAsync(null);

        Assert.Equal(["Plan:RestoreBackup"], actions.Calls);
        Assert.Empty(confirm.Shown);
        Assert.Equal("Unsupported", vm.LastOutcome?.Result);
        Assert.Equal("BackupMetadataMissing", vm.LastOutcome?.MessageCode);
    });

    [Fact]
    public void FailuresOfTheActionAreShown() => RunOnDispatcher(async () =>
    {
        var (vm, _, actions, _) = Create(true, Backup("id-1", "Jan"));
        actions.PlanFailure = new InvalidOperationException("Modul nicht erreichbar");
        await vm.LoadAsync();
        vm.SelectedItem = vm.Items[0];

        await vm.DeleteCommand.ExecuteAsync(null);

        Assert.Equal("Failed", vm.LastOutcome?.Result);
        Assert.Equal("Modul nicht erreichbar", vm.LastOutcome?.Message);
        Assert.False(vm.IsBusy);
    });

    [Fact]
    public void ReloadingWhileAnActionRunsDoesNotReleaseTheBusyFlag() => RunOnDispatcher(async () =>
    {
        var (vm, _, actions, confirm) = Create(true, Backup("id-1", "Jan"));
        actions.Plan = Planned("RemoveBackup", "id-1");
        actions.Hold = new TaskCompletionSource();
        await vm.LoadAsync();
        vm.SelectedItem = vm.Items[0];

        var running = vm.DeleteCommand.ExecuteAsync(null);
        while (!actions.Calls.Contains("Execute:RemoveBackup:id-1"))
        {
            await Task.Delay(10);
        }
        Assert.True(vm.IsBusy);
        await vm.LoadAsync();
        Assert.True(vm.IsBusy, "Neu laden (z. B. beim Seitenwechsel) darf die laufende Aktion nicht freigeben");
        Assert.False(vm.DeleteCommand.CanExecute(null));

        actions.Hold.SetResult();
        await running;
        Assert.False(vm.IsBusy);
        Assert.Single(confirm.Shown);
    });

    [Fact]
    public void ConfirmationDialogShowsTheDescriptionInsteadOfTheBackupId()
    {
        var restore = Planned("RestoreBackup", "00000000-0000-0000-0000-000000000001");
        Assert.Equal("Beschreibung", restore.ConfirmText);
        var update = new ActionOutcome { Action = "Update", Name = "x", Result = "Planned", CommandLine = "winget upgrade", Message = "egal" };
        Assert.Equal("winget upgrade", update.ConfirmText);
    }

    [Fact]
    public void OpeningTheBackupsTabReadsTheListWithoutAnyScan() => RunOnDispatcher(async () =>
    {
        var (vm, backups, _, _) = Create(true, Backup("id-1", "Jan"));
        var shell = new ShellViewModel(null!, null!, null, vm);

        shell.SelectedTab = ShellViewModel.SettingsTab;
        Assert.Equal(0, backups.Loads);
        shell.SelectedTab = ShellViewModel.BackupsTab;
        while (backups.Loads == 0)
        {
            await Task.Delay(10);
        }
        Assert.Equal(1, backups.Loads);
        await Task.Delay(50);
        Assert.Single(vm.Items);
    });

    private sealed class FakeBackups : IBackupService
    {
        public IReadOnlyList<RegistryBackupItem> Items { get; set; } = [];
        public Exception? Failure { get; set; }
        public int Loads { get; private set; }

        public async Task<IReadOnlyList<RegistryBackupItem>> GetBackupsAsync(CancellationToken cancellationToken = default)
        {
            await Task.Yield();
            Loads++;
            return Failure is null ? Items : throw Failure;
        }
    }

    private sealed class FakeActions : IActionService
    {
        public ActionOutcome Plan { get; set; } = Planned("RemoveBackup", "id-1");
        public ActionOutcome Outcome { get; set; } = new() { Action = "RemoveBackup", Name = "Jan", Result = "Succeeded" };
        public Exception? PlanFailure { get; set; }
        public TaskCompletionSource? Hold { get; set; }
        public List<string> Calls { get; } = [];

        public async Task<ActionOutcome> PlanAsync(SoftwareActionKind kind, PSObject? source, string method = "Auto", CancellationToken cancellationToken = default)
        {
            await Task.Yield();
            Calls.Add($"Plan:{kind}");
            return PlanFailure is null ? Plan : throw PlanFailure;
        }

        public async Task<ActionOutcome> ExecuteAsync(SoftwareActionKind kind, PSObject? source, ActionOutcome confirmedPlan, string method = "Auto", System.Collections.Hashtable? control = null, CancellationToken cancellationToken = default)
        {
            await Task.Yield();
            Calls.Add($"Execute:{kind}:{confirmedPlan.CommandLine}");
            if (Hold is not null)
            {
                await Hold.Task;
            }
            return Outcome;
        }

        public Task<int> UpdateIncompleteLogAsync(CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<SoftwareItem?> RecheckAsync(PSObject source, CancellationToken cancellationToken = default, bool refresh = false) => throw new NotSupportedException();
        public Task ClearCheckCacheAsync(PSObject source, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<StoreAgreement> GetStoreAgreementAsync(CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task AcceptStoreAgreementAsync(CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<IReadOnlyList<QueueEntry>> PlanUpdateQueueAsync(IReadOnlyList<PSObject> sources, IProgress<string>? progress = null, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<IReadOnlyList<ActionOutcome>> RunUpdateQueueAsync(IReadOnlyList<QueueEntry> entries, System.Collections.Hashtable control, IProgress<string>? progress = null) => throw new NotSupportedException();
        public Task<IReadOnlyList<ActionHistoryEntry>> GetHistoryAsync(string name, CancellationToken cancellationToken = default) => throw new NotSupportedException();
    }

    private sealed class FakeConfirm : IConfirmationService
    {
        public bool Answer { get; set; } = true;
        public List<ActionOutcome> Shown { get; } = [];

        public bool Confirm(ActionOutcome plan)
        {
            Shown.Add(plan);
            return Answer;
        }

        public Task<bool> ConfirmRefreshAsync(RefreshEstimate estimate) => throw new NotSupportedException();
        public bool ConfirmQueue(QueueConfirmation confirmation) => throw new NotSupportedException();
        public bool ConfirmStoreAgreement(StoreAgreement agreement) => throw new NotSupportedException();
        public CpeMappingChoice? ChooseCpe(CpeMappingViewModel viewModel) => throw new NotSupportedException();
        public Task<bool> ConfirmCpeReportAsync(CpeReport report) => throw new NotSupportedException();
    }
}
