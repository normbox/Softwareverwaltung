using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Softwareverwaltung.App.Localization;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Services;

namespace Softwareverwaltung.App.ViewModels;

/// <summary>
/// Fenster „CPE zuordnen“: unbestätigte Vorschläge aus der NVD oder eigene Eingabe. Übernommen wird
/// nur, was der Benutzer mit „Zuordnen“ bestätigt; Vorschläge werden nie automatisch genutzt.
/// </summary>
public sealed partial class CpeMappingViewModel(SoftwareItem item, ICpeService cpe) : ObservableObject
{
    public SoftwareItem Item { get; } = item;

    public string Title => AppText.Format("CpeMappingHeading", Item.Name);

    public string ProgramText => string.Join(" · ", new[] { Item.Publisher, Item.InstalledVersion, Item.WingetId }.Where(p => !string.IsNullOrWhiteSpace(p)));

    /// <summary>Bestehende, vom Benutzer bestätigte Zuordnung (kann entfernt werden).</summary>
    public string? CurrentCpe => Item.HasUserCpe ? string.Join(", ", Item.CpeBase) : null;

    public ObservableCollection<CpeCandidate> Candidates { get; } = [];

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowHint))]
    private bool _isSearching;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowHint))]
    private string? _hint;

    public bool ShowHint => !IsSearching && Hint is not null;

    [ObservableProperty]
    private CpeCandidate? _selectedCandidate;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsCpeValid), nameof(ShowCpeInvalid))]
    [NotifyCanExecuteChangedFor(nameof(AssignCommand))]
    private string _cpeText = "";

    public bool IsCpeValid => CpeName.IsValid(CpeText);

    public bool ShowCpeInvalid => CpeText.Trim().Length > 0 && !IsCpeValid;

    /// <summary>Auswahl des Benutzers; null = abgebrochen.</summary>
    public CpeMappingChoice? Choice { get; private set; }

    /// <summary>Schließt das Fenster (gesetzt vom Fenster).</summary>
    public event EventHandler? CloseRequested;

    // Ein Vorschlag füllt nur das Eingabefeld; übernommen wird erst mit „Zuordnen“.
    partial void OnSelectedCandidateChanged(CpeCandidate? value)
    {
        if (value is not null)
        {
            CpeText = value.Cpe;
        }
    }

    public async Task SearchAsync()
    {
        IsSearching = true;
        Hint = null;
        try
        {
            var result = await cpe.FindCandidatesAsync(Item.Source!);
            Candidates.Clear();
            foreach (var candidate in result.Candidates)
            {
                Candidates.Add(candidate);
            }
            Hint = result.Hint;
        }
        catch (Exception ex)
        {
            Hint = AppText.Format("CpeSearchFailed", ex.Message);
        }
        finally
        {
            IsSearching = false;
        }
    }

    [RelayCommand(CanExecute = nameof(IsCpeValid))]
    private void Assign()
    {
        Choice = CpeMappingChoice.Assign(CpeText.Trim());
        CloseRequested?.Invoke(this, EventArgs.Empty);
    }

    [RelayCommand]
    private void Remove()
    {
        Choice = CpeMappingChoice.RemoveMapping;
        CloseRequested?.Invoke(this, EventArgs.Empty);
    }
}
