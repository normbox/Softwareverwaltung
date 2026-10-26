function Get-LocalizedString {
    <#
    .SYNOPSIS
        Text aus SoftwareInventory.Strings.psd1 in der Sprache der Oberfläche, mit Platzhaltern {0}, {1} ….
    .DESCRIPTION
        Fehlt ein Schlüssel, kommt der Schlüssel selbst zurück (fällt in Tests und in der Anzeige auf,
        statt still leer zu bleiben).
    #>
    param(
        [Parameter(Mandatory)] [string] $Name,
        [object[]] $Arguments = @()
    )
    $text = if ($script:Strings) { $script:Strings[$Name] }
    if (-not $text) { return $Name }
    if ($Arguments.Count) { $text -f $Arguments } else { $text }
}
