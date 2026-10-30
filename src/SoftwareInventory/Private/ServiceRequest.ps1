# Gemeinsame Schicht für alle Anfragen an externe Dienste: prüft die Freigabe, setzt Schlüssel
# nur als Header, drosselt, speichert Antworten zwischen und hält Schlüssel aus Fehlermeldungen.

# Mindestabstand zwischen zwei Anfragen je Dienst (Sekunden): ohne / mit Schlüssel.
$script:ServiceInterval = @{
    NVD    = @{ Anonymous = 6.0; WithKey = 0.6 }   # NVD: 5 bzw. 50 Anfragen pro 30 s
    CIRCL  = @{ Anonymous = 3.0; WithKey = 1.5 }   # CIRCL: 20 bzw. 40 Anfragen pro Minute
    GitHub = @{ Anonymous = 0.0; WithKey = 0.0 }
    KEV    = @{ Anonymous = 0.0; WithKey = 0.0 }
    EPSS   = @{ Anonymous = 0.0; WithKey = 0.0 }
}
$script:LastServiceCall = @{}
# Bei 429 mit Retry-After bis zu dieser Wartezeit (Sekunden) einmal warten und wiederholen; sonst Zwischenspeicher.
$script:MaxRetryAfterSeconds = 60

# Zwischenspeicher-Steuerung je Lauf (siehe CacheTrace.ps1):
#   CacheRefresh – $null: Cache normal nutzen; sonst Menge der in diesem Lauf schon frisch geholten Dateien
#                  (jede Antwort wird pro Lauf höchstens einmal neu geholt, z. B. der KEV-Katalog).
#   CheckTrace   – Liste der für das aktuelle Programm benutzten Einträge (Dienst, Datei, Abrufzeit, veraltet).
$script:CacheRefresh = $null
$script:CheckTrace = $null
# Dienst → Schlüssel in den Einstellungen (CacheHours)
$script:CacheHoursKey = @{ GitHub = 'LatestVersion'; WingetSearch = 'LatestVersion'; NVD = 'NVD'; CIRCL = 'CIRCL'; EPSS = 'EPSS'; KEV = 'KEV' }

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
        -MaxAge wiederverwendet (Standard: Haltbarkeit des Dienstes aus den Einstellungen, CacheHours).
        Bei Neu prüfen (CacheRefresh) wird jede Antwort pro Lauf einmal frisch geholt. Ist der Dienst
        nicht erreichbar oder am Anfragelimit, wird ein abgelaufener Eintrag verwendet und im Mitschrieb
        als veraltet gekennzeichnet. Antwortet ein Dienst mit 429 und Retry-After bis 60 Sekunden, wird
        einmal so lange gewartet und die Anfrage wiederholt. Fehler werden als ServiceRequestException mit Grund
        (Disabled, RateLimit, NotFound, Http, Network) geworfen; Schlüssel sind entfernt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('GitHub', 'NVD', 'CIRCL', 'KEV', 'EPSS', 'WingetSearch')] [string] $Service,
        [Parameter(Mandatory)] [uri] $Uri,
        [string] $CacheKey,
        # Ohne Angabe: Haltbarkeit des Dienstes aus den Einstellungen
        [Nullable[timespan]] $MaxAge,
        $Setting = (Read-InventorySetting)
    )

    if (-not (Test-ServiceEnabled -Name $Service -Setting $Setting)) {
        throw (New-ServiceRequestException -Service $Service -Reason Disabled -Message (Get-LocalizedString 'ServiceErrorDisabled' $Service))
    }

    if ($null -eq $MaxAge) { $MaxAge = Get-CacheMaxAge -Service $Service -Setting $Setting }
    $cacheFile = $null
    $entry = $null
    if ($CacheKey) {
        $cacheFile = Get-ServiceCacheFile -Service $Service -CacheKey $CacheKey
        $entry = Read-ServiceCacheEntry -Path $cacheFile
        if ($entry -and -not (Test-CacheRefresh $cacheFile) -and ([datetime]::UtcNow - $entry.FetchedAt) -le $MaxAge) {
            Write-Verbose "$Service aus Zwischenspeicher: $CacheKey"
            Write-CheckStep -Key StepCached -Arguments $Service
            Add-CheckTrace -Service $Service -File $cacheFile -FetchedAt $entry.FetchedAt -MaxAge $MaxAge
            return $entry.Data
        }
    }

    $secret = if ($Service -in 'NVD', 'CIRCL', 'GitHub') { Get-ServiceSecret -Service $Service }
    # Mit Kontakt-URL, wie CIRCL es für automatische Abfragen erwartet
    $module = Get-Module SoftwareInventory
    $headers = @{ 'User-Agent' = "SoftwareInventory/$($module.Version) (+$($module.PrivateData.PSData.ProjectUri))" }
    switch ($Service) {
        'GitHub' {
            $headers.Accept = 'application/vnd.github+json'
            if ($secret) { $headers.Authorization = "Bearer $secret" }
        }
        'NVD' { if ($secret) { $headers.apiKey = $secret } }
        'CIRCL' { if ($secret) { $headers['X-API-KEY'] = $secret } }
    }

    # Die englischen Fortschrittsmeldungen von Invoke-WebRequest nicht anzeigen; den Fortschritt
    # melden die Prüfungen selbst (Write-CheckProgress).
    $ProgressPreference = 'SilentlyContinue'
    Write-Verbose "$Service-Anfrage: $($Uri.GetLeftPart([UriPartial]::Path))"
    $response = $null
    for ($attempt = 1; -not $response; $attempt++) {
        Wait-ServiceInterval -Service $Service -HasKey ([bool] $secret)
        try {
            $response = Invoke-WebRequest -Uri $Uri -Headers $headers -TimeoutSec 60 -ErrorAction Stop
        }
        catch {
            $failure = ConvertTo-ServiceRequestException -Service $Service -ErrorRecord $_
            $retryAfter = $failure.Data['RetryAfter']
            if ($attempt -eq 1 -and $null -ne $retryAfter -and $retryAfter -le $script:MaxRetryAfterSeconds) {
                Write-Verbose "$Service am Anfragelimit, warte $retryAfter s und wiederhole einmal"
                Write-CheckStep -Key StepWaitRetryAfter -Arguments $Service, ([Math]::Max(1, $retryAfter))
                Start-Sleep -Seconds ([Math]::Max(1, $retryAfter))
                continue
            }
            # Offline oder Anfragelimit: lieber alte Daten, als veraltet gekennzeichnet, als gar keine.
            if ($entry -and $failure.Data['Reason'] -in 'Network', 'RateLimit', 'Http') {
                Write-Verbose "$Service nicht erreichbar, verwende Zwischenspeicher vom $($entry.FetchedAt.ToString('o'))"
                Add-CheckTrace -Service $Service -File $cacheFile -FetchedAt $entry.FetchedAt -MaxAge $MaxAge
                return $entry.Data
            }
            throw $failure
        }
    }

    $content = [string] $response.Content
    # NVD-Antworten verschlankt speichern und auch sofort so auswerten, damit frische und
    # zwischengespeicherte Daten gleich aussehen.
    if ($Service -eq 'NVD') { $content = ConvertTo-NvdCacheContent $content }
    $data = $content | ConvertFrom-Json -DateKind String
    if ($cacheFile) {
        Write-ServiceCache -Path $cacheFile -Content $content
        Add-CheckTrace -Service $Service -File $cacheFile -FetchedAt ([datetime]::UtcNow) -MaxAge $MaxAge
    }
    $data
}

function Get-ServiceCacheFile {
    param([string] $Service, [string] $CacheKey)
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($CacheKey)))
    Join-Path (Join-Path (Get-CacheDirectory) $Service) "$hash.json"
}

function Get-CacheMaxAge {
    # Haltbarkeit eines Dienstes aus den Einstellungen (CacheHours), sonst der Standard.
    param([string] $Service, $Setting)
    $key = $script:CacheHoursKey[$Service]
    $hours = if ($key -and $Setting -and $Setting.PSObject.Properties['CacheHours'] -and $Setting.CacheHours) { $Setting.CacheHours.$key -as [int] }
    if (-not $hours -and $key) { $hours = $script:DefaultCacheHours[$key] }
    if (-not $hours) { $hours = 24 }
    [timespan]::FromHours($hours)
}

function Wait-ServiceInterval {
    param([string] $Service, [bool] $HasKey)
    $interval = if ($HasKey) { $script:ServiceInterval[$Service].WithKey } else { $script:ServiceInterval[$Service].Anonymous }
    if ($interval -le 0) { return }
    $last = $script:LastServiceCall[$Service]
    if ($last) {
        $wait = $interval - ([datetime]::UtcNow - $last).TotalSeconds
        if ($wait -gt 0) {
            # Kurze Pausen nicht anzeigen, längere an den aktuellen Schritt hängen
            if ($wait -ge 1) { Write-CheckStep -Key StepWaitInterval -Arguments ([int] [Math]::Ceiling($wait)), $Service -Wait }
            Start-Sleep -Milliseconds ([int] ($wait * 1000))
        }
    }
    $script:LastServiceCall[$Service] = [datetime]::UtcNow
}

function Read-ServiceCacheEntry {
    # Eintrag samt Abrufzeit (UTC), unabhängig vom Alter; $null, wenn keiner da oder unlesbar.
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $entry = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -DateKind String
        $fetched = [datetime]::Parse($entry.FetchedAt, [cultureinfo]::InvariantCulture, 'RoundtripKind').ToUniversalTime()
        @{ FetchedAt = $fetched; Data = ($entry.Content | ConvertFrom-Json -DateKind String) }
    }
    catch {
        Write-Verbose "Zwischenspeicher unlesbar, wird neu geladen: $Path"
        $null
    }
}

function Read-ServiceCache {
    # Daten eines Eintrags, solange er jünger als -MaxAge ist.
    param([string] $Path, [timespan] $MaxAge)
    $entry = Read-ServiceCacheEntry -Path $Path
    if (-not $entry -or [datetime]::UtcNow - $entry.FetchedAt -gt $MaxAge) { return $null }
    $entry.Data
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
        return New-ServiceRequestException -Service $Service -Reason Network -Message (Get-LocalizedString 'ServiceErrorNetwork' $Service, $ErrorRecord.Exception.Message)
    }
    $status = [int] $response.StatusCode
    $remaining = $null
    $values = $null
    if ($response.Headers.TryGetValues('X-RateLimit-Remaining', [ref] $values)) { $remaining = @($values)[0] }
    if ($status -eq 429 -or ($status -eq 403 -and $remaining -eq '0')) {
        $exception = New-ServiceRequestException -Service $Service -Reason RateLimit -Message (Get-LocalizedString 'ServiceErrorRateLimit' $Service, $status)
        if ($status -eq 429) { $exception.Data['RetryAfter'] = Get-RetryAfterSecond $response }
        return $exception
    }
    if ($status -eq 404) {
        return New-ServiceRequestException -Service $Service -Reason NotFound -Message (Get-LocalizedString 'ServiceErrorNotFound' $Service)
    }
    New-ServiceRequestException -Service $Service -Reason Http -Message (Get-LocalizedString 'ServiceErrorHttp' $Service, $status)
}

function Get-RetryAfterSecond {
    # Wartezeit aus Retry-After in ganzen Sekunden (Angabe in Sekunden oder als HTTP-Datum), sonst $null.
    param($Response)
    $retry = $Response.Headers.RetryAfter
    if (-not $retry) { return $null }
    if ($null -ne $retry.Delta) { return [int] [Math]::Ceiling($retry.Delta.TotalSeconds) }
    if ($null -ne $retry.Date) { return [int] [Math]::Max(0, [Math]::Ceiling(($retry.Date - [datetimeoffset]::UtcNow).TotalSeconds)) }
    $null
}

function Get-ServiceErrorReason {
    # Grund aus einer Ausnahme von Invoke-ServiceRequest, sonst 'Http'.
    param($ErrorRecord)
    $reason = $ErrorRecord.Exception.Data['Reason']
    if ($reason) { $reason } else { 'Http' }
}
