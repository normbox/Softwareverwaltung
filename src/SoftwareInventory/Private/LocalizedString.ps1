function Get-LocalizedString {
    <#
    .SYNOPSIS
        Text aus SoftwareInventory.Strings.psd1 in der Sprache der Oberfläche, mit Platzhaltern {0}, {1} ….
    .DESCRIPTION
        Fehlt ein Schlüssel, kommt der Schlüssel selbst zurück (fällt in Tests und in der Anzeige auf,
        statt still leer zu bleiben).
        Einzahl: Gibt es den Schlüssel zusätzlich mit „One“ (z. B. ReasonKnownVulnerabilitiesOne) und
        ist das erste Argument die Zahl 1, wird dieser Text genommen; sonst der Text in Mehrzahl.
    #>
    param(
        [Parameter(Mandatory)] [string] $Name,
        [object[]] $Arguments = @()
    )
    $text = if ($script:Strings) { $script:Strings[$Name] }
    $one = if ($script:Strings -and $Arguments.Count -and [string] $Arguments[0] -eq '1') { $script:Strings["${Name}One"] }
    if ($one) { $text = $one }
    if (-not $text) { return $Name }
    if ($Arguments.Count) { $text -f $Arguments } else { $text }
}
