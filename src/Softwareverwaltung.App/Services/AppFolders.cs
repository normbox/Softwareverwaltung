using System.IO;

namespace Softwareverwaltung.App.Services;

/// <summary>
/// App-Ordner wie im Modul: %APPDATA% bzw. %LOCALAPPDATA% aus der Umgebung, sonst der Windows-Ordner.
/// So schreiben App und Modul immer in denselben Ordner, auch wenn die Umgebung umgelenkt ist (z. B. bei Tests
/// mit temporärem APPDATA; Environment.GetFolderPath allein würde die Umgebungsvariable übergehen).
/// </summary>
public static class AppFolders
{
    /// <summary>%APPDATA%\SoftwareInventory (Einstellungen der App und des Moduls).</summary>
    public static string Roaming => Path.Combine(Resolve(Environment.GetEnvironmentVariable("APPDATA"), Environment.SpecialFolder.ApplicationData), "SoftwareInventory");

    /// <summary>%LOCALAPPDATA%\SoftwareInventory (Logs und Zwischenspeicher).</summary>
    public static string Local => Path.Combine(Resolve(Environment.GetEnvironmentVariable("LOCALAPPDATA"), Environment.SpecialFolder.LocalApplicationData), "SoftwareInventory");

    /// <summary>Gesetzte Umgebungsvariable mit vollständigem Pfad, sonst der Windows-Ordner.</summary>
    public static string Resolve(string? environmentValue, Environment.SpecialFolder fallback) =>
        !string.IsNullOrWhiteSpace(environmentValue) && Path.IsPathFullyQualified(environmentValue)
            ? environmentValue
            : Environment.GetFolderPath(fallback);
}
