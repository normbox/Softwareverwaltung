using CommunityToolkit.Mvvm.ComponentModel;

namespace Softwareverwaltung.App.ViewModels;

/// <summary>Hauptfenster mit den Seiten „Programme“ und „Einstellungen“ und der Seitenleiste des KI-Beraters.</summary>
public sealed partial class ShellViewModel : ObservableObject
{
    public const int ProgramsTab = 0;
    public const int SettingsTab = 1;

    public ShellViewModel(MainViewModel programs, SettingsViewModel settings, AdvisorChatViewModel? advisor = null)
    {
        Programs = programs;
        Settings = settings;
        Advisor = advisor;
        if (advisor is not null)
        {
            advisor.OpenSettingsRequested += (_, _) => SelectedTab = SettingsTab;
        }
    }

    public MainViewModel Programs { get; }

    public SettingsViewModel Settings { get; }

    /// <summary>Seitenleiste des Beraters; ohne sie (Tests) bleibt der Knopf verborgen.</summary>
    public AdvisorChatViewModel? Advisor { get; }

    [ObservableProperty]
    private int _selectedTab = ProgramsTab;

    /// <summary>
    /// Module laden, dann Einstellungen (für die Frage Privat/Firma). Gescannt wird erst, wenn der
    /// Benutzer „Scannen“ wählt: Ein Scan fragt externe Dienste ab und soll nie von selbst starten.
    /// </summary>
    public async Task InitializeAsync()
    {
        if (!await Programs.LoadModulesAsync())
        {
            return;
        }
        await Settings.LoadAsync();
    }
}
