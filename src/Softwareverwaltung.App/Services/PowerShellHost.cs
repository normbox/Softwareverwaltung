using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using Softwareverwaltung.App.Localization;

namespace Softwareverwaltung.App.Services;

/// <summary>
/// Eingebettete PowerShell-Engine (Microsoft.PowerShell.SDK) mit dem Kern-Modul.
/// Eine Runspace wird wiederverwendet; Aufrufe laufen nacheinander im Hintergrund,
/// damit die Oberfläche nie blockiert. Fachlogik liegt ausschließlich im Modul.
/// </summary>
public sealed class PowerShellHost : IPowerShellHost
{
    public const string CoreModuleName = "SoftwareInventory";
    public const string WinGetModuleName = "Microsoft.WinGet.Client";

    private readonly string _modulesDirectory;
    private readonly SemaphoreSlim _lock = new(1, 1);
    private Runspace? _runspace;
    private bool _disposed;

    public PowerShellHost(string? modulesDirectory = null)
    {
        _modulesDirectory = modulesDirectory ?? Path.Combine(AppContext.BaseDirectory, "Modules");
    }

    /// <summary>Warnungen und Fehler beim Laden der Module (z. B. winget-Modul fehlt).</summary>
    public IReadOnlyList<string> StartupMessages { get; private set; } = [];

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await _lock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (_runspace is not null)
            {
                return;
            }

            var core = FindModuleManifest(CoreModuleName)
                ?? throw new FileNotFoundException(AppText.Format("ErrorCoreModuleNotFound", _modulesDirectory));
            var winget = FindModuleManifest(WinGetModuleName);

            // CreateDefault enthält die eingebauten Cmdlets ohne Modulsuche; die App bringt kein $PSHOME mit.
            var state = InitialSessionState.CreateDefault();
            // Nur für diese Sitzung: Das Modul ist nicht signiert. Systemweit ändert sich nichts.
            state.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            state.ThreadOptions = PSThreadOptions.ReuseThread;

            var runspace = RunspaceFactory.CreateRunspace(state);
            runspace.ApartmentState = ApartmentState.MTA;
            await Task.Run(runspace.Open, cancellationToken).ConfigureAwait(false);
            await SetModulePathAsync(runspace, BuildModulePath(_modulesDirectory)).ConfigureAwait(false);

            var messages = new List<string>();
            // CimCmdlets (Get-CimInstance …) kommt sonst aus einem installierten PowerShell 7; die DLL liefert das SDK mit.
            var cim = Path.Combine(AppContext.BaseDirectory, "Microsoft.Management.Infrastructure.CimCmdlets.dll");
            if (File.Exists(cim))
            {
                messages.AddRange(await ImportAsync(runspace, cim, required: false).ConfigureAwait(false));
            }
            // Mitgelieferte Module mit vollem Pfad laden, damit keine andere installierte Version gewinnt.
            if (winget is not null)
            {
                messages.AddRange(await ImportAsync(runspace, winget, required: false).ConfigureAwait(false));
            }
            else
            {
                messages.Add(AppText.Format("WarningWinGetModuleMissing", WinGetModuleName));
            }
            messages.AddRange(await ImportAsync(runspace, core, required: true).ConfigureAwait(false));

            StartupMessages = messages;
            _runspace = runspace;
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task<PowerShellResult> InvokeAsync(PSCommand command, IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var runspace = _runspace ?? throw new InvalidOperationException(AppText.Get("ErrorHostNotInitialized"));

        await _lock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            using var ps = PowerShell.Create();
            ps.Runspace = runspace;
            ps.Commands = command;
            if (progress is not null)
            {
                ps.Streams.Progress.DataAdded += (_, e) =>
                {
                    var record = ps.Streams.Progress[e.Index];
                    if (record.RecordType != ProgressRecordType.Completed)
                    {
                        progress.Report(string.IsNullOrWhiteSpace(record.StatusDescription) ? record.Activity : $"{record.Activity}: {record.StatusDescription}");
                    }
                };
            }

            using var registration = cancellationToken.Register(() => ps.BeginStop(null, null));
            var output = new List<PSObject>();
            var errors = new List<string>();
            var cancelled = false;
            try
            {
                output.AddRange(await Task.Run(() => ps.Invoke(), CancellationToken.None).ConfigureAwait(false));
            }
            catch (PipelineStoppedException)
            {
                cancelled = true;
            }
            catch (RuntimeException ex)
            {
                errors.Add(ex.ErrorRecord?.ToString() ?? ex.Message);
            }

            errors.AddRange(ps.Streams.Error.Select(e => e.ToString()));
            var warnings = ps.Streams.Warning.Select(w => w.Message).ToList();
            if (cancelled || cancellationToken.IsCancellationRequested)
            {
                throw new OperationCanceledException(cancellationToken);
            }
            return new PowerShellResult(output, errors, warnings);
        }
        finally
        {
            _lock.Release();
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _runspace?.Dispose();
        _lock.Dispose();
    }

    /// <summary>
    /// Modulpfad der eingebetteten Engine: nur die mitgelieferten Module und die Windows-Module aus
    /// System32 (z. B. Appx für Store-Apps). Ohne Bereinigung erbt die Engine den Pfad des startenden
    /// Prozesses (Benutzermodule, installiertes PowerShell 7, Program Files) und könnte fremde Module laden.
    /// </summary>
    public static string BuildModulePath(string modulesDirectory)
    {
        var windowsModules = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "Modules");
        return string.Join(Path.PathSeparator, modulesDirectory, windowsModules);
    }

    private static Task SetModulePathAsync(Runspace runspace, string modulePath) => Task.Run(() =>
    {
        // Gilt für die ganze App (Prozessumgebung), damit auch der erhöhte Helfer (powershell.exe) ihn erbt.
        using var ps = PowerShell.Create();
        ps.Runspace = runspace;
        ps.AddScript("param($Path) $env:PSModulePath = $Path").AddParameter("Path", modulePath);
        ps.Invoke();
    });

    private string? FindModuleManifest(string name)
    {
        var root = Path.Combine(_modulesDirectory, name);
        if (!Directory.Exists(root))
        {
            return null;
        }
        // Mit oder ohne Versionsordner (Modules\Name\1.2.3\Name.psd1).
        return Directory.EnumerateFiles(root, name + ".psd1", SearchOption.AllDirectories)
            .OrderByDescending(p => p, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();
    }

    private static Task<List<string>> ImportAsync(Runspace runspace, string manifest, bool required) => Task.Run(() =>
    {
        using var ps = PowerShell.Create();
        ps.Runspace = runspace;
        ps.AddCommand("Import-Module").AddParameter("Name", manifest).AddParameter("Force");
        var messages = new List<string>();
        try
        {
            ps.Invoke();
        }
        catch (RuntimeException ex) when (!required)
        {
            messages.Add(AppText.Format("WarningModuleLoadFailed", Path.GetFileNameWithoutExtension(manifest), ex.Message));
        }
        if (required && ps.HadErrors && ps.Streams.Error.Count > 0)
        {
            throw new InvalidOperationException(AppText.Format("ErrorCoreModuleLoadFailed", ps.Streams.Error[0]));
        }
        messages.AddRange(ps.Streams.Error.Select(e => AppText.Format("WarningModuleError", Path.GetFileNameWithoutExtension(manifest), e)));
        messages.AddRange(ps.Streams.Warning.Select(w => w.Message));
        return messages;
    });
}
