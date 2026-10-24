function Compare-SoftwareVersion {
    <#
    .SYNOPSIS
        Vergleicht zwei Versionsangaben: -1 (älter), 0 (gleich), 1 (neuer) oder $null (unbekannt).
    .DESCRIPTION
        Zahlenteile werden numerisch verglichen, nachgestellte Nullen zählen nicht
        (24.08 = 24.8.0.0). Präfixe wie „v“ und Zusätze wie „(x64)“ oder „+build“ werden
        ignoriert. Vorabversionen (alpha, beta, rc …) sind älter als die Release-Version,
        ein Patch-Buchstabe (1.1.1w) ist neuer. Ist eine Angabe nicht lesbar, ist das
        Ergebnis $null – nie „gleich“.
    .EXAMPLE
        Compare-SoftwareVersion -Reference '24.08' -Difference '24.9'    # -1
    .EXAMPLE
        Compare-SoftwareVersion 'v8.9.8.1' '8.9.8.1'                     # 0
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory, Position = 0)] [AllowNull()] [AllowEmptyString()] [string] $Reference,
        [Parameter(Mandatory, Position = 1)] [AllowNull()] [AllowEmptyString()] [string] $Difference
    )

    $a = ConvertTo-NormalizedVersion $Reference
    $b = ConvertTo-NormalizedVersion $Difference
    if (-not $a -or -not $b) { return $null }
    Compare-NormalizedVersion -Reference $a -Difference $b
}
