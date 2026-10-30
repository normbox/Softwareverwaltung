namespace Softwareverwaltung.App.ViewModels;

/// <summary>Hauptfenster mit den Seiten „Programme“ und „Einstellungen“.</summary>
public sealed class ShellViewModel(MainViewModel programs, SettingsViewModel settings)
{
    public MainViewModel Programs { get; } = programs;

    public SettingsViewModel Settings { get; } = settings;

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
