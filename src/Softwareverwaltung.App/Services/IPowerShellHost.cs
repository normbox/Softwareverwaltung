using System.Management.Automation;

namespace Softwareverwaltung.App.Services;

public interface IPowerShellHost : IDisposable
{
    IReadOnlyList<string> StartupMessages { get; }

    Task InitializeAsync(CancellationToken cancellationToken = default);

    /// <summary>Führt Befehle des Moduls aus. Fehler und Warnungen kommen im Ergebnis zurück, nicht als Ausnahme.</summary>
    Task<PowerShellResult> InvokeAsync(PSCommand command, IProgress<string>? progress = null, CancellationToken cancellationToken = default);
}

public sealed record PowerShellResult(IReadOnlyList<PSObject> Output, IReadOnlyList<string> Errors, IReadOnlyList<string> Warnings);
