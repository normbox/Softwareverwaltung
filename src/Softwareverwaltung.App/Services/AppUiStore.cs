using System.IO;
using System.Text.Json;

namespace Softwareverwaltung.App.Services;

/// <summary>Einstellungen nur der Oberfläche, z. B. die Breite des Detailfelds.</summary>
public sealed record AppUiSettings
{
    /// <summary>Breite des Detailfelds als Anteil der Listenbreite (Start 40 %).</summary>
    public double DetailsWidthFraction { get; init; } = DefaultDetailsWidthFraction;

    public const double DefaultDetailsWidthFraction = 0.4;
    public const double MinDetailsWidthFraction = 0.15;
    public const double MaxDetailsWidthFraction = 0.9;
    /// <summary>Mindestbreite des Detailfelds in Pixeln, auch in schmalen Fenstern.</summary>
    public const double MinDetailsWidth = 360;

    /// <summary>Anteil auf den erlaubten Bereich begrenzt; ungültige Werte ergeben den Startwert.</summary>
    public static double ClampFraction(double value) =>
        double.IsFinite(value) ? Math.Clamp(value, MinDetailsWidthFraction, MaxDetailsWidthFraction) : DefaultDetailsWidthFraction;
}

public interface IAppUiStore
{
    AppUiSettings Load();

    void Save(AppUiSettings settings);
}

/// <summary>
/// Liest und schreibt %APPDATA%\SoftwareInventory\app-ui.json. Gehört nur der App, nicht den
/// Moduleinstellungen (settings.json). Fehlt die Datei oder ist sie unlesbar, gelten die Startwerte.
/// </summary>
public sealed class AppUiStore(string? path = null) : IAppUiStore
{
    private readonly string _path = path ?? Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "SoftwareInventory", "app-ui.json");

    public AppUiSettings Load()
    {
        try
        {
            if (!File.Exists(_path))
            {
                return new AppUiSettings();
            }
            var loaded = JsonSerializer.Deserialize<AppUiSettings>(File.ReadAllText(_path)) ?? new AppUiSettings();
            return loaded with { DetailsWidthFraction = AppUiSettings.ClampFraction(loaded.DetailsWidthFraction) };
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
        {
            return new AppUiSettings();
        }
    }

    public void Save(AppUiSettings settings)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            File.WriteAllText(_path, JsonSerializer.Serialize(settings with { DetailsWidthFraction = AppUiSettings.ClampFraction(settings.DetailsWidthFraction) }));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Nur eine Bequemlichkeit: Ohne gespeicherte Breite startet das Feld beim nächsten Mal mit 40 %.
            ErrorLog.Write("AppUiStore", ex);
        }
    }
}

/// <summary>Ohne Datei (Tests, Vorschau): hält die Werte nur im Speicher.</summary>
public sealed class MemoryAppUiStore : IAppUiStore
{
    public AppUiSettings Current { get; private set; } = new();

    public AppUiSettings Load() => Current;

    public void Save(AppUiSettings settings) => Current = settings;
}
