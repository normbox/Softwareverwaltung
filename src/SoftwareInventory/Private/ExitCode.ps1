# Exit-Codes von winget, msiexec und Deinstallationsprogrammen, abgebildet auf einheitliche Ausgänge.
# Ein Ausgang ist nur ein Zwischenstand: Ob eine Aktion wirklich gelungen ist, entscheidet erst die
# Prüfung des Zustands danach (siehe Resolve-ActionResult).
#   Success, SuccessReboot, Cancelled, NotInstalled, NoUpdate, Failed
# winget-Codes laut https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md

$script:ExitCodeMap = @{
    # Windows / Windows Installer
    '0'          = @{ Outcome = 'Success'; Message = 'Erfolgreich beendet' }
    '3010'       = @{ Outcome = 'SuccessReboot'; Message = 'Erfolgreich, ein Neustart ist nötig' }
    '1641'       = @{ Outcome = 'SuccessReboot'; Message = 'Erfolgreich, das Installationsprogramm hat einen Neustart eingeleitet' }
    '1602'       = @{ Outcome = 'Cancelled'; Message = 'Vom Benutzer abgebrochen' }
    '1223'       = @{ Outcome = 'Cancelled'; Message = 'Vom Benutzer abgebrochen' }
    '1605'       = @{ Outcome = 'NotInstalled'; Message = 'Das Produkt ist nicht installiert' }
    '1614'       = @{ Outcome = 'NotInstalled'; Message = 'Das Produkt ist bereits deinstalliert' }
    '1603'       = @{ Outcome = 'Failed'; Message = 'Schwerer Fehler im Installationsprogramm (MSI 1603)' }
    '1618'       = @{ Outcome = 'Failed'; Message = 'Eine andere Installation läuft gerade; später erneut versuchen' }
    '1619'       = @{ Outcome = 'Failed'; Message = 'Installationspaket konnte nicht geöffnet werden' }
    '1638'       = @{ Outcome = 'Failed'; Message = 'Eine andere Version des Produkts ist bereits installiert' }
    '740'        = @{ Outcome = 'Failed'; Message = 'Das Programm verlangt Administratorrechte' }
    # winget
    '0x8A15002B' = @{ Outcome = 'NoUpdate'; Message = 'winget: kein passendes Update gefunden' }
    '0x8A15004F' = @{ Outcome = 'NoUpdate'; Message = 'winget: die verfügbare Version ist nicht neuer als die installierte' }
    '0x8A150014' = @{ Outcome = 'NotInstalled'; Message = 'winget: Paket nicht gefunden' }
    '0x8A150017' = @{ Outcome = 'Failed'; Message = 'winget: kein Manifest für diese ID gefunden' }
    '0x8A150010' = @{ Outcome = 'Failed'; Message = 'winget: kein Installationsprogramm passt zu diesem System' }
    '0x8A150011' = @{ Outcome = 'Failed'; Message = 'winget: Prüfsumme des Installationsprogramms stimmt nicht (abgebrochen)' }
    '0x8A15002D' = @{ Outcome = 'Failed'; Message = 'winget: Installationsprogramm hat die Sicherheitsprüfung nicht bestanden' }
    '0x8A150008' = @{ Outcome = 'Failed'; Message = 'winget: Download fehlgeschlagen' }
    '0x8A150019' = @{ Outcome = 'Failed'; Message = 'winget: Befehl verlangt Administratorrechte' }
    '0x8A150056' = @{ Outcome = 'Failed'; Message = 'winget: das Installationsprogramm darf nicht mit Administratorrechten laufen' }
    '0x8A15007D' = @{ Outcome = 'Failed'; Message = 'winget: Pakete im Benutzerbereich dürfen nicht aus einem Administratorkontext geändert werden' }
    '0x8A15002F' = @{ Outcome = 'Failed'; Message = 'winget: kein Deinstallationsbefehl gefunden' }
    '0x8A150030' = @{ Outcome = 'Failed'; Message = 'winget: Deinstallationsbefehl ist fehlgeschlagen' }
    '0x8A150041' = @{ Outcome = 'Failed'; Message = 'winget: Paketvereinbarung nicht akzeptiert' }
    '0x8A150046' = @{ Outcome = 'Failed'; Message = 'winget: Quellvereinbarung nicht akzeptiert' }
    '0x8A15003A' = @{ Outcome = 'Failed'; Message = 'winget: durch Gruppenrichtlinie blockiert' }
    '0x8A15001B' = @{ Outcome = 'Failed'; Message = 'winget: Microsoft Store durch Richtlinie blockiert' }
    '0x8A15001C' = @{ Outcome = 'Failed'; Message = 'winget: Store-App durch Richtlinie blockiert' }
    '0x8A150068' = @{ Outcome = 'Failed'; Message = 'winget: das Paket ist angeheftet (pin) und wird nicht aktualisiert' }
    '0x8A15008E' = @{ Outcome = 'Failed'; Message = 'winget: das Update nutzt eine andere Installationstechnik als die installierte Version' }
    '0x8A15006D' = @{ Outcome = 'Failed'; Message = 'winget: ein benötigter Dienst ist ausgelastet; später erneut versuchen' }
    '0x8A150005' = @{ Outcome = 'Cancelled'; Message = 'winget: abgebrochen' }
    '0x8A150101' = @{ Outcome = 'Failed'; Message = 'Das Programm läuft noch; bitte beenden und erneut versuchen' }
    '0x8A150111' = @{ Outcome = 'Failed'; Message = 'Das Programm wird von einer anderen Anwendung benutzt' }
    '0x8A150102' = @{ Outcome = 'Failed'; Message = 'Eine andere Installation läuft gerade; später erneut versuchen' }
    '0x8A150103' = @{ Outcome = 'Failed'; Message = 'Dateien sind in Benutzung; Programm beenden und erneut versuchen' }
    '0x8A150104' = @{ Outcome = 'Failed'; Message = 'Eine Abhängigkeit fehlt' }
    '0x8A150105' = @{ Outcome = 'Failed'; Message = 'Nicht genug Speicherplatz' }
    '0x8A150106' = @{ Outcome = 'Failed'; Message = 'Nicht genug Arbeitsspeicher' }
    '0x8A150107' = @{ Outcome = 'Failed'; Message = 'Keine Netzwerkverbindung' }
    '0x8A150108' = @{ Outcome = 'Failed'; Message = 'Fehler im Installationsprogramm; Hersteller kontaktieren' }
    '0x8A150109' = @{ Outcome = 'SuccessReboot'; Message = 'Neustart nötig, um abzuschließen' }
    '0x8A15010A' = @{ Outcome = 'Failed'; Message = 'Erst neu starten, dann erneut versuchen' }
    '0x8A15010B' = @{ Outcome = 'SuccessReboot'; Message = 'Der PC wird neu gestartet, um abzuschließen' }
    '0x8A15010C' = @{ Outcome = 'Cancelled'; Message = 'Vom Benutzer abgebrochen' }
    '0x8A15010D' = @{ Outcome = 'Failed'; Message = 'Eine andere Version ist bereits installiert' }
    '0x8A15010E' = @{ Outcome = 'Failed'; Message = 'Eine höhere Version ist bereits installiert' }
    '0x8A15010F' = @{ Outcome = 'Failed'; Message = 'Durch Richtlinien der Organisation blockiert' }
    '0x8A150110' = @{ Outcome = 'Failed'; Message = 'Abhängigkeiten konnten nicht installiert werden' }
    '0x8A150113' = @{ Outcome = 'Failed'; Message = 'Paket wird von diesem System nicht unterstützt' }
    '0x8A150114' = @{ Outcome = 'Failed'; Message = 'Das Installationsprogramm kann die vorhandene Version nicht aktualisieren' }
    '0x8A150115' = @{ Outcome = 'Failed'; Message = 'Installationsprogramm meldet einen eigenen Fehler' }
}

function Format-ExitCode {
    # Kleine Codes dezimal (3010), große als HRESULT in Hex (0x8A15002B).
    param([Parameter(Mandatory)] [long] $ExitCode)
    $unsigned = if ($ExitCode -lt 0) { $ExitCode + 4294967296 } else { $ExitCode }
    if ($unsigned -le 65535) { return [string] $unsigned }
    '0x{0:X8}' -f [long] $unsigned
}

function ConvertFrom-ActionExitCode {
    <#
    .SYNOPSIS
        Bildet einen Exit-Code auf einen einheitlichen Ausgang samt Klartext ab.
    .OUTPUTS
        @{ Outcome; Message; Code } – Code ist die Schreibweise aus Format-ExitCode.
    #>
    param([Parameter(Mandatory)] [long] $ExitCode)
    $code = Format-ExitCode $ExitCode
    $entry = $script:ExitCodeMap[$code]
    if ($entry) { return @{ Outcome = $entry.Outcome; Message = $entry.Message; Code = $code } }
    @{ Outcome = 'Failed'; Message = "Unbekannter Exit-Code $code"; Code = $code }
}
