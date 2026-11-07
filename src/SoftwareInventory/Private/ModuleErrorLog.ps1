# Fehlerprotokoll des Moduls für Fälle ohne Meldung an den Benutzer (z. B. unlesbarer Zwischenspeicher):
# dieselbe Datei wie das Fehlerprotokoll der App, %LOCALAPPDATA%\SoftwareInventory\logs\app-errors-<Datum>.log.
# Räumt sich mit logs\ auf. Schreibt nie Schlüssel oder Antworten von Diensten.

function Write-ModuleErrorLog {
    param([Parameter(Mandatory)] [string] $Origin, [Parameter(Mandatory)] [string] $Message)
    try {
        $directory = Join-Path (Get-AppDataDirectory) 'logs'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $now = [datetime]::Now
        $path = Join-Path $directory "app-errors-$($now.ToString('yyyyMMdd')).log"
        $nl = [Environment]::NewLine
        [System.IO.File]::AppendAllText($path, "[$($now.ToString('yyyy-MM-dd HH:mm:ss'))] Modul/$Origin$nl$(Protect-SecretText $Message)$nl$nl", [System.Text.UTF8Encoding]::new($false))
    }
    catch { Write-Verbose "Fehlerprotokoll nicht schreibbar: $($_.Exception.Message)" }
}
