using System.Windows.Input;

namespace Softwareverwaltung.App.Models;

public enum NoticeSeverity
{
    Informational,
    Warning,
    Error,
}

/// <summary>Hinweis oben im Fenster, z. B. „winget fehlt“ oder Warnungen des Moduls; optional mit Link und Button.</summary>
public sealed record Notice(NoticeSeverity Severity, string Title, string Message, string? LinkText = null, Uri? Link = null,
    string? ActionText = null, ICommand? Action = null);
