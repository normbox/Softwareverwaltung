namespace Softwareverwaltung.App.Services;

/// <summary>
/// Schreibt unerwartete Fehler mit vollständigen Details in den App-Ordner
/// (%LOCALAPPDATA%\SoftwareInventory\logs). Das Modul räumt diesen Ordner beim Start selbst auf.
/// </summary>
public static class ErrorLog
{
    public static string Directory { get; set; } =
        Path.Combine(AppFolders.Local, "logs");

    /// <summary>Liefert den Pfad der Logdatei oder null, wenn nicht geschrieben werden konnte. Wirft nie.</summary>
    public static string? Write(string origin, Exception? exception) =>
        Append($"{origin}{Environment.NewLine}{exception?.ToString() ?? "(keine Ausnahme)"}");

    /// <summary>
    /// Vermerkt ein Ereignis ohne Ausnahme mit festem Code (z. B. „Shutdown: StopTimeout“), damit es
    /// sich später nachvollziehen lässt. Liefert den Pfad oder null. Wirft nie.
    /// </summary>
    public static string? WriteEvent(string origin, string code) => Append($"{origin}: {code}");

    private static string? Append(string body)
    {
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            var path = Path.Combine(Directory, $"app-errors-{DateTime.Now:yyyyMMdd}.log");
            File.AppendAllText(path, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {body}{Environment.NewLine}{Environment.NewLine}");
            return path;
        }
        catch (Exception)
        {
            return null;
        }
    }
}
