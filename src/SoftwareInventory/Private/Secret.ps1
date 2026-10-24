# API-Schlüssel und Tokens. Sie sind optional, kommen nur aus Umgebungsvariablen und dürfen
# nie in Protokollen, Snapshots, Berichten oder Fehlermeldungen erscheinen (siehe CLAUDE.md).
# Die Windows-Anmeldeinformationsverwaltung folgt mit der Oberfläche (Etappe 3).

$script:SecretVariable = @{
    NVD    = 'NVD_API_KEY'
    GitHub = 'GITHUB_TOKEN'
}

function Get-ServiceSecret {
    # Liefert den Schlüssel oder $null. Der Rückgabewert darf nur in Request-Header wandern.
    param([Parameter(Mandatory)] [ValidateSet('NVD', 'GitHub')] [string] $Service)
    $value = [Environment]::GetEnvironmentVariable($script:SecretVariable[$Service])
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    $value.Trim()
}

function Protect-SecretText {
    <#
    .SYNOPSIS
        Ersetzt bekannte Schlüssel in einem Text durch „***“.
    .DESCRIPTION
        Schutznetz für Fehlermeldungen und ausführliche Ausgaben: Selbst wenn ein Schlüssel
        über eine Ausnahme in einen Text gerät, wird er vor der Ausgabe entfernt.
    #>
    param([AllowNull()] [AllowEmptyString()] [string] $Text)
    if (-not $Text) { return $Text }
    foreach ($service in $script:SecretVariable.Keys) {
        $secret = Get-ServiceSecret -Service $service
        if ($secret) { $Text = $Text.Replace($secret, '***') }
    }
    $Text
}
