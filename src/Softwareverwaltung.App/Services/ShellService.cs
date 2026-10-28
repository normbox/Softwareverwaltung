using System.Diagnostics;
using System.Windows;

namespace Softwareverwaltung.App.Services;

/// <summary>Ordner im Explorer öffnen und Text in die Zwischenablage legen (eigene Schnittstelle für Tests).</summary>
public interface IShellService
{
    void OpenFolder(string path);

    void CopyText(string text);
}

public sealed class ShellService : IShellService
{
    public void OpenFolder(string path)
    {
        // Nur vorhandene Ordner, nie Dateien: der Explorer soll nichts starten.
        if (!Directory.Exists(path))
        {
            return;
        }
        var start = new ProcessStartInfo("explorer.exe") { UseShellExecute = false };
        start.ArgumentList.Add(path);
        Process.Start(start)?.Dispose();
    }

    public void CopyText(string text) => Clipboard.SetText(text);
}
