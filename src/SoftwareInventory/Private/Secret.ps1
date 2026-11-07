# API-Schlüssel und Tokens. Sie sind optional und dürfen nie in Protokollen, Snapshots,
# Berichten oder Fehlermeldungen erscheinen (siehe CLAUDE.md).
# Reihenfolge: Windows-Anmeldeinformationsverwaltung zuerst, dann Umgebungsvariable (für Skripte/Tests).

$script:SecretVariable = @{
    NVD     = 'NVD_API_KEY'
    CIRCL   = 'CIRCL_API_KEY'   # optional, verdoppelt das Anfragelimit von CIRCL Vulnerability-Lookup
    GitHub  = 'GITHUB_TOKEN'
    Advisor = 'SOFTWAREINVENTORY_ADVISOR_KEY'   # optional, für lokale KI-Server mit Schlüssel (z. B. Unsloth Studio)
}
# Eintrag in der Anmeldeinformationsverwaltung: <Präfix>/<Dienst>, Typ „Generisch“, nur dieser Benutzer.
$script:CredentialPrefix = 'SoftwareInventory'

# Zugriff auf die Anmeldeinformationsverwaltung: [SoftwareInventory.CredentialStore] aus
# lib\SoftwareInventory.Native.dll (RequiredAssemblies im Manifest), fertig übersetzt statt Add-Type.

function Get-CredentialTarget {
    param([Parameter(Mandatory)] [string] $Service)
    "$script:CredentialPrefix/$Service"
}

function Read-StoredSecret {
    # Schlüssel aus der Anmeldeinformationsverwaltung oder $null. Lesefehler gelten als „kein Schlüssel“.
    param([Parameter(Mandatory)] [string] $Service)
    try {
        $value = [SoftwareInventory.CredentialStore]::Read((Get-CredentialTarget $Service))
    }
    catch {
        Write-Verbose "Anmeldeinformationsverwaltung nicht lesbar ($Service): $($_.Exception.Message)"
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    $value.Trim()
}

function Read-EnvironmentSecret {
    param([Parameter(Mandatory)] [string] $Service)
    $value = [Environment]::GetEnvironmentVariable($script:SecretVariable[$Service])
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    $value.Trim()
}

function Get-ServiceSecret {
    # Liefert den Schlüssel oder $null. Der Rückgabewert darf nur in Request-Header wandern.
    param([Parameter(Mandatory)] [ValidateSet('NVD', 'CIRCL', 'GitHub', 'Advisor')] [string] $Service)
    $stored = Read-StoredSecret -Service $Service
    if ($stored) { return $stored }
    Read-EnvironmentSecret -Service $Service
}

function Protect-SecretText {
    <#
    .SYNOPSIS
        Ersetzt bekannte Schlüssel in einem Text durch „***“.
    .DESCRIPTION
        Schutznetz für Fehlermeldungen und ausführliche Ausgaben: Selbst wenn ein Schlüssel
        über eine Ausnahme in einen Text gerät, wird er vor der Ausgabe entfernt. Maskiert
        werden Schlüssel aus beiden Ablagen, auch wenn nur einer davon benutzt wird.
    #>
    param([AllowNull()] [AllowEmptyString()] [string] $Text)
    if (-not $Text) { return $Text }
    foreach ($service in $script:SecretVariable.Keys) {
        foreach ($secret in @((Read-StoredSecret -Service $service), (Read-EnvironmentSecret -Service $service))) {
            if ($secret) { $Text = $Text.Replace($secret, '***') }
        }
    }
    $Text
}
