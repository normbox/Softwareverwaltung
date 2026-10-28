# Gründe, Status und Hinweise als feste Codes (CLAUDE.md „Mehrsprachig vorbereitet“): Logik und Tests
# prüfen nur Code, angezeigt wird Text in der Sprache der Oberfläche (Schlüssel Reason<Code> in
# SoftwareInventory.Strings.psd1).

function New-InventoryMessage {
    <#
    .SYNOPSIS
        Erzeugt eine Meldung mit Code, Args und Text.
    .DESCRIPTION
        Args darf weitere Meldungen enthalten (z. B. „Nicht auf Lücken geprüft: <Grund>“); sie bleiben
        als Objekte mit Code erhalten und gehen mit ihrem Text in den Text ein. Eine Liste von
        Meldungen wird mit „; “ verbunden.
    .EXAMPLE
        New-InventoryMessage ServiceDisabled 'NVD'
    .EXAMPLE
        New-InventoryMessage CriticalCvss $cveId, $score
    #>
    param(
        [Parameter(Mandatory, Position = 0)] [string] $Code,
        [Parameter(Position = 1)] [AllowEmptyCollection()] [object[]] $Arguments = @()
    )
    $values = @(foreach ($a in $Arguments) { ConvertTo-MessageText $a })
    [pscustomobject] @{
        PSTypeName = 'SoftwareInventory.Message'
        Code       = $Code
        Args       = @($Arguments)
        Text       = Get-LocalizedString "Reason$Code" $values
    }
}

function ConvertTo-MessageText {
    # Text einer Meldung, einer Liste von Meldungen oder eines einfachen Werts.
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return (@($Value | ForEach-Object { ConvertTo-MessageText $_ }) -join '; ')
    }
    if (Test-InventoryMessage $Value) { return [string] $Value.Text }
    # Zahlen wie bisher invariant (CVSS 9.8), Kulturformat erst in der Anzeige.
    [string] $Value
}

function ConvertTo-MessageData {
    # Schlichte Daten für JSON (KI-Berater): code, args, text; verschachtelte Meldungen ebenso.
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        # Liste wird ausgerollt; Aufrufer fassen mit @() wieder zusammen.
        return @($Value | ForEach-Object { ConvertTo-MessageData $_ })
    }
    if (-not (Test-InventoryMessage $Value)) { return $Value }
    [ordered]@{
        code = $Value.Code
        args = @($Value.Args | ForEach-Object { ConvertTo-MessageData $_ })
        text = $Value.Text
    }
}

function ConvertFrom-MessageData {
    <#
    .SYNOPSIS
        Baut eine gespeicherte Meldung (Aktionsprotokoll, Ergebnis des erhöhten Helfers) neu auf.
    .DESCRIPTION
        Gespeichert sind Code und Args; der Text entsteht neu in der Sprache der Oberfläche. Reiner Text
        ohne Code stammt aus älteren Protokollen und wird als LegacyText („… (älterer Eintrag)“) gekennzeichnet.
    #>
    param($Value)
    if ($null -eq $Value -or ($Value -is [string] -and -not $Value)) { return $null }
    if ($Value -is [string]) { return New-InventoryMessage LegacyText $Value }
    $code = if ($Value -is [System.Collections.IDictionary]) { $Value['Code'] } else { $Value.PSObject.Properties['Code']?.Value }
    if (-not $code) { return New-InventoryMessage LegacyText ([string] $Value) }
    $stored = if ($Value -is [System.Collections.IDictionary]) { $Value['Args'] } else { $Value.PSObject.Properties['Args']?.Value }
    $arguments = @(if ($null -ne $stored) {
            foreach ($a in @($stored)) {
                if ($null -ne $a -and $a -isnot [string] -and ($a -is [System.Collections.IDictionary] -or $a.PSObject.Properties['Code'])) { ConvertFrom-MessageData $a }
                else { $a }
            }
        })
    New-InventoryMessage $code $arguments
}

function Test-InventoryMessage {
    param($Value)
    $null -ne $Value -and $Value -isnot [string] -and $null -ne $Value.PSObject.Properties['Code'] -and $null -ne $Value.PSObject.Properties['Text']
}
