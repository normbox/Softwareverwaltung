function Get-LocalizedString {
    <#
    .SYNOPSIS
        Text aus SoftwareInventory.Strings.psd1 in der Sprache der Oberfläche, mit Platzhaltern {0}, {1} ….
    .DESCRIPTION
        Fehlt ein Schlüssel, kommt der Schlüssel selbst zurück (fällt in Tests und in der Anzeige auf,
        statt still leer zu bleiben).
        Einzahl: Gibt es den Schlüssel zusätzlich mit „One“ (z. B. ReasonKnownVulnerabilitiesOne) und
        ist das erste Argument die Zahl 1, wird dieser Text genommen; sonst der Text in Mehrzahl.
        Wirft nie: Passen die Argumente nicht zu den Platzhaltern (z. B. zu wenige aus einer beschädigten Datei oder
        der Antwort einer anderen Helferversion), kommt der Text ohne eingesetzte Argumente zurück und das
        Fehlerprotokoll des Moduls bekommt einen Eintrag (nur Schlüssel und Anzahl, keine Inhalte).
    #>
    param(
        [Parameter(Mandatory)] [string] $Name,
        [object[]] $Arguments = @()
    )
    $text = Get-LocalizedTemplate -Name $Name -Arguments $Arguments
    if (-not $text) { return $Name }
    if (-not $Arguments.Count) { return $text }
    $formatted = Format-LocalizedTemplate -Text $text -Arguments $Arguments
    if ($formatted.Ok) { return $formatted.Text }
    Write-ModuleErrorLog -Origin 'Get-LocalizedString' -Message "Text $Name`: $($Arguments.Count) Argument(e) passen nicht zu den Platzhaltern."
    $text
}

function Get-LocalizedTemplate {
    # Der Text zum Schlüssel (mit Einzahl-Variante „One“), noch ohne Argumente; $null, wenn es ihn nicht gibt.
    param([string] $Name, [object[]] $Arguments = @())
    $text = if ($script:Strings) { $script:Strings[$Name] }
    $one = if ($script:Strings -and $Arguments.Count -and [string] $Arguments[0] -eq '1') { $script:Strings["${Name}One"] }
    if ($one) { $text = $one }
    $text
}

function Format-LocalizedTemplate {
    <#
    .SYNOPSIS
        Argumente einsetzen, ohne zu werfen: @{ Ok; Text }.
    .DESCRIPTION
        Erst die Platzhalter zählen ({0}, {1:N0}, …; {{ und }} sind keine): Verlangt der Text mehr Argumente als da sind,
        wird gar nicht formatiert. So entsteht keine Ausnahme, die PowerShell auch abgefangen noch in -ErrorVariable und
        $Error vermerkt. Der try/catch fängt nur noch Texte mit kaputtem Format ab (nicht bei den Texten der psd1).
    #>
    param([string] $Text, [object[]] $Arguments = @())
    $needed = 0
    foreach ($match in [regex]::Matches(($Text -replace '\{\{|\}\}', ''), '\{(\d+)')) {
        $needed = [Math]::Max($needed, [int] $match.Groups[1].Value + 1)
    }
    if ($needed -gt $Arguments.Count) { return @{ Ok = $false; Text = $Text } }
    try { @{ Ok = $true; Text = ($Text -f $Arguments) } }
    catch { @{ Ok = $false; Text = $Text } }
}

function Test-InventoryMessageArgs {
    <#
    .SYNOPSIS
        Lassen sich die Argumente in den Text der Meldung mit diesem Code einsetzen (Schlüssel Reason<Code>)?
    .DESCRIPTION
        Für Codes und Argumente von außen (Begleitdateien, Aktionsprotokoll): Passen sie nicht, ist die Quelle
        beschädigt. Ein unbekannter Code gilt als passend (Get-LocalizedString zeigt dann den Schlüssel).
    #>
    param([Parameter(Mandatory)] [string] $Code, [object[]] $Arguments = @())
    $text = Get-LocalizedTemplate -Name "Reason$Code" -Arguments $Arguments
    if (-not $text) { return $true }
    (Format-LocalizedTemplate -Text $text -Arguments $Arguments).Ok
}
