using Microsoft.Win32;

namespace Softwareverwaltung.App.Services;

public interface IFolderPicker
{
    /// <summary>Zeigt den Windows-Dialog zur Ordnerauswahl; null, wenn abgebrochen.</summary>
    string? PickFolder();
}

public sealed class FolderPicker : IFolderPicker
{
    public string? PickFolder()
    {
        var dialog = new OpenFolderDialog { Multiselect = false };
        return dialog.ShowDialog() == true ? dialog.FolderName : null;
    }
}
