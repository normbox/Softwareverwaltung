# Gemeinsame Schicht für alle Anfragen an externe Dienste: prüft die Freigabe, setzt Schlüssel
# nur als Header, drosselt, speichert Antworten zwischen und hält Schlüssel aus Fehlermeldungen.

# Mindestabstand zwischen zwei Anfragen je Dienst (Sekunden): ohne / mit Schlüssel.
$script:ServiceInterval = @{
    NVD    = @{ Anonymous = 6.0; WithKey = 0.6 }   # NVD: 5 bzw. 50 Anfragen pro 30 s
    GitHub = @{ Anonymous = 0.0; WithKey = 0.0 }
    KEV    = @{ Anonymous = 0.0; WithKey = 0.0 }
    EPSS   = @{ Anonymous = 0.0; WithKey = 0.0 }
}
$script:LastServiceCall = @{}

function Get-CacheDirectory {
    Join-Path $env:LOCALAPPDATA 'SoftwareInventory\cache'
}

function Invoke-ServiceRequest {
    <#
    .SYNOPSIS
        Ruft eine JSON-Schnittstelle eines externen Dienstes ab.
    .DESCRIPTION
        Bricht ab, wenn der Dienst in den Einstellungen nicht aktiviert ist. Mit -CacheKey
        wird die Antwort unter %LOCALAPPDATA%\SoftwareInventory\cache gespeichert und bis
        -MaxAge wiederverwendet. Fehler werden als ServiceRequestException mit Grund
        (Disabled, RateLimit, NotFound, Http, Network) geworfen; Schlüssel sind entfernt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('GitHub', 'NVD', 'KEV', 'EPSS', 'WingetSearch')] [string] $Service,
        [Parameter(Mandatory)] [uri] $Uri,
        [string] $CacheKey,
        [timespan] $MaxAge = [timespan]::FromHours(12),
        $Setting = (Read-InventorySetting)
    )

    if (-not (Test-ServiceEnabled -Name $Service -Setting $Setting)) {
        throw (New-ServiceRequestException -Service $Service -Reason Disabled -Message "Dienst $Service ist nicht aktiviert.")
    }

    $cacheFile = $null
    if ($CacheKey) {
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($CacheKey)))
        $cacheFile = Join-Path (Join-Path (Get-CacheDirectory) $Service) "$hash.json"
        $cached = Read-ServiceCache -Path $cacheFile -MaxAge $MaxAge
        if ($null -ne $cached) {
            Write-Verbose "$Service aus Zwischenspeicher: $CacheKey"
            return $cached
        }
    }

    $secret = if ($Service -in 'NVD', 'GitHub') { Get-ServiceSecret -Service $Service }
    $headers = @{ 'User-Agent' = "SoftwareInventory/$((Get-Module SoftwareInventory).Version)" }
    switch ($Service) {
        'GitHub' {
            $headers.Accept = 'application/vnd.github+json'
            if ($secret) { $headers.Authorization = "Bearer $secret" }
        }
        'NVD' { if ($secret) { $headers.apiKey = $secret } }
    }

    Wait-ServiceInterval -Service $Service -HasKey ([bool] $secret)
    Write-Verbose "$Service-Anfrage: $($Uri.GetLeftPart([UriPartial]::Path))"
    try {
        $response = Invoke-WebRequest -Uri $Uri -Headers $headers -TimeoutSec 60 -ErrorAction Stop
    }
    catch {
        throw (ConvertTo-ServiceRequestException -Service $Service -ErrorRecord $_)
    }

    $content = [string] $response.Content
    $data = $content | ConvertFrom-Json -DateKind String
    if ($cacheFile) { Write-ServiceCache -Path $cacheFile -Content $content }
    $data
}

function Wait-ServiceInterval {
    param([string] $Service, [bool] $HasKey)
    $interval = if ($HasKey) { $script:ServiceInterval[$Service].WithKey } else { $script:ServiceInterval[$Service].Anonymous }
    if ($interval -le 0) { return }
    $last = $script:LastServiceCall[$Service]
    if ($last) {
        $wait = $interval - ([datetime]::UtcNow - $last).TotalSeconds
        if ($wait -gt 0) { Start-Sleep -Milliseconds ([int] ($wait * 1000)) }
    }
    $script:LastServiceCall[$Service] = [datetime]::UtcNow
}

function Read-ServiceCache {
    param([string] $Path, [timespan] $MaxAge)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $entry = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -DateKind String
        $fetched = [datetime]::Parse($entry.FetchedAt, [cultureinfo]::InvariantCulture, 'RoundtripKind')
        if ([datetime]::UtcNow - $fetched -gt $MaxAge) { return $null }
        $entry.Content | ConvertFrom-Json -DateKind String
    }
    catch {
        Write-Verbose "Zwischenspeicher unlesbar, wird neu geladen: $Path"
        $null
    }
}

function Write-ServiceCache {
    # Gespeichert wird nur die Antwort, nie die Anfrage samt Kopfzeilen.
    param([string] $Path, [string] $Content)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [pscustomobject] @{ FetchedAt = [datetime]::UtcNow.ToString('o'); Content = $Content } |
        ConvertTo-Json -Depth 2 -Compress | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

function New-ServiceRequestException {
    param([string] $Service, [ValidateSet('Disabled', 'RateLimit', 'NotFound', 'Http', 'Network')] [string] $Reason, [string] $Message)
    $exception = [System.Exception]::new((Protect-SecretText $Message))
    $exception.Data['Service'] = $Service
    $exception.Data['Reason'] = $Reason
    $exception
}

function ConvertTo-ServiceRequestException {
    # Übersetzt einen Fehler von Invoke-WebRequest in eine Meldung ohne Schlüssel und Kopfzeilen.
    param([string] $Service, [System.Management.Automation.ErrorRecord] $ErrorRecord)
    $response = $ErrorRecord.Exception.PSObject.Properties['Response']?.Value
    if (-not $response) {
        return New-ServiceRequestException -Service $Service -Reason Network -Message "$Service nicht erreichbar: $($ErrorRecord.Exception.Message)"
    }
    $status = [int] $response.StatusCode
    $remaining = $null
    $values = $null
    if ($response.Headers.TryGetValues('X-RateLimit-Remaining', [ref] $values)) { $remaining = @($values)[0] }
    if ($status -eq 429 -or ($status -eq 403 -and $remaining -eq '0')) {
        return New-ServiceRequestException -Service $Service -Reason RateLimit -Message "$Service-Anfragelimit erreicht (HTTP $status)."
    }
    if ($status -eq 404) {
        return New-ServiceRequestException -Service $Service -Reason NotFound -Message "${Service}: nicht gefunden (HTTP 404)."
    }
    New-ServiceRequestException -Service $Service -Reason Http -Message "$Service antwortet mit HTTP $status."
}

function Get-ServiceErrorReason {
    # Grund aus einer Ausnahme von Invoke-ServiceRequest, sonst 'Http'.
    param($ErrorRecord)
    $reason = $ErrorRecord.Exception.Data['Reason']
    if ($reason) { $reason } else { 'Http' }
}
