# Exit-Codes von winget, msiexec und Deinstallationsprogrammen, abgebildet auf einheitliche Ausgänge.
# Die Texte stehen in SoftwareInventory.Strings.psd1 (ReasonExitCode<Code>).
# Ein Ausgang ist nur ein Zwischenstand: Ob eine Aktion wirklich gelungen ist, entscheidet erst die
# Prüfung des Zustands danach (siehe Resolve-ActionResult).
#   Success, SuccessReboot, Cancelled, NotInstalled, NoUpdate, Failed
# winget-Codes laut https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md

$script:ExitCodeMap = @{
    # Windows / Windows Installer
    '0'          = @{ Outcome = 'Success' }
    '3010'       = @{ Outcome = 'SuccessReboot' }
    '1641'       = @{ Outcome = 'SuccessReboot' }
    '1602'       = @{ Outcome = 'Cancelled' }
    '1223'       = @{ Outcome = 'Cancelled' }
    '1605'       = @{ Outcome = 'NotInstalled' }
    '1614'       = @{ Outcome = 'NotInstalled' }
    '1603'       = @{ Outcome = 'Failed' }
    '1618'       = @{ Outcome = 'Failed' }
    '1619'       = @{ Outcome = 'Failed' }
    '1638'       = @{ Outcome = 'Failed' }
    '740'        = @{ Outcome = 'Failed' }
    # winget
    '0x8A15002B' = @{ Outcome = 'NoUpdate' }
    '0x8A15004F' = @{ Outcome = 'NoUpdate' }
    '0x8A150014' = @{ Outcome = 'NotInstalled' }
    '0x8A150017' = @{ Outcome = 'Failed' }
    '0x8A150010' = @{ Outcome = 'Failed' }
    '0x8A150011' = @{ Outcome = 'Failed' }
    '0x8A15002D' = @{ Outcome = 'Failed' }
    '0x8A150008' = @{ Outcome = 'Failed' }
    '0x8A150019' = @{ Outcome = 'Failed' }
    '0x8A150056' = @{ Outcome = 'Failed' }
    '0x8A15007D' = @{ Outcome = 'Failed' }
    '0x8A15002F' = @{ Outcome = 'Failed' }
    '0x8A150030' = @{ Outcome = 'Failed' }
    '0x8A150041' = @{ Outcome = 'Failed' }
    '0x8A150046' = @{ Outcome = 'Failed' }
    '0x8A15003A' = @{ Outcome = 'Failed' }
    '0x8A15001B' = @{ Outcome = 'Failed' }
    '0x8A15001C' = @{ Outcome = 'Failed' }
    '0x8A150068' = @{ Outcome = 'Failed' }
    '0x8A15008E' = @{ Outcome = 'Failed' }
    '0x8A15006D' = @{ Outcome = 'Failed' }
    '0x8A150005' = @{ Outcome = 'Cancelled' }
    '0x8A150101' = @{ Outcome = 'Failed' }
    '0x8A150111' = @{ Outcome = 'Failed' }
    '0x8A150102' = @{ Outcome = 'Failed' }
    '0x8A150103' = @{ Outcome = 'Failed' }
    '0x8A150104' = @{ Outcome = 'Failed' }
    '0x8A150105' = @{ Outcome = 'Failed' }
    '0x8A150106' = @{ Outcome = 'Failed' }
    '0x8A150107' = @{ Outcome = 'Failed' }
    '0x8A150108' = @{ Outcome = 'Failed' }
    '0x8A150109' = @{ Outcome = 'SuccessReboot' }
    '0x8A15010A' = @{ Outcome = 'Failed' }
    '0x8A15010B' = @{ Outcome = 'SuccessReboot' }
    '0x8A15010C' = @{ Outcome = 'Cancelled' }
    '0x8A15010D' = @{ Outcome = 'Failed' }
    '0x8A15010E' = @{ Outcome = 'Failed' }
    '0x8A15010F' = @{ Outcome = 'Failed' }
    '0x8A150110' = @{ Outcome = 'Failed' }
    '0x8A150113' = @{ Outcome = 'Failed' }
    '0x8A150114' = @{ Outcome = 'Failed' }
    '0x8A150115' = @{ Outcome = 'Failed' }
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
        @{ Outcome; Message; Code } – Message ist eine Meldung (Code ExitCode<Code>), Code die Schreibweise aus Format-ExitCode.
    #>
    param([Parameter(Mandatory)] [long] $ExitCode)
    $code = Format-ExitCode $ExitCode
    $entry = $script:ExitCodeMap[$code]
    if ($entry) { return @{ Outcome = $entry.Outcome; Message = (New-InventoryMessage "ExitCode$code"); Code = $code } }
    @{ Outcome = 'Failed'; Message = (New-InventoryMessage ExitCodeUnknown $code); Code = $code }
}
