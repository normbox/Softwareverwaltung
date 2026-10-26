using System.Windows;
using Softwareverwaltung.App.Models;
using Softwareverwaltung.App.Views;

namespace Softwareverwaltung.App.Services;

public interface IConfirmationService
{
    /// <summary>Zeigt den geplanten Befehl und fragt, ob er ausgeführt werden soll.</summary>
    bool Confirm(ActionOutcome plan);
}

public sealed class ConfirmationService : IConfirmationService
{
    public bool Confirm(ActionOutcome plan)
    {
        var dialog = new ConfirmActionWindow { DataContext = plan, Owner = Application.Current?.MainWindow };
        return dialog.ShowDialog() == true;
    }
}
