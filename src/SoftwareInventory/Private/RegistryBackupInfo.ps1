# Angaben zu einer Sicherung (Get-RegistryBackup) und gemeinsame Teile von Restore-/Remove-RegistryBackup.

function Find-RegistryBackupFile {
    # Sucht die Sicherung anhand ihrer Kennung (GUID) an beiden Orten (Eigenschaft BackupScope). Nie ein Pfad vom Aufrufer.
    param([string] $Id)
    $guid = [guid]::Empty
    if (-not [guid]::TryParseExact($Id, 'D', [ref] $guid)) { return $null }
    Get-RegistryBackupFile | Where-Object { (Get-RegistryBackupId $_.Name) -eq $guid.ToString() } | Select-Object -First 1
}

function Get-LegacyBackupDetail {
    # Ältere Sicherung ohne Begleitdatei (aus #55): Name und Schlüssel aus der .reg-Datei, sonst aus dem Dateinamen.
    param([System.IO.FileInfo] $File, $Text)
    $name = $null; $key = $null
    if ($Text) {
        foreach ($line in $Text -split "\r?\n") {
            $t = $line.Trim()
            if (-not $key -and $t -match '^\[(?<k>[^-].*)\]$') { $key = $Matches.k; continue }
            if ($key -and -not $name -and $t -match '^"DisplayName"="(?<v>(?:[^"\\]|\\.)*)"$') {
                $name = $Matches.v -replace '\\(["\\])', '$1'
                break
            }
        }
    }
    if (-not $name) { $name = [System.IO.Path]::GetFileNameWithoutExtension($File.Name) -replace '^[0-9a-fA-F-]{36}_', '' }
    if ($name.Length -gt 200) { $name = $name.Substring(0, 200) }
    @{ Name = $name; NativeKey = $key }
}

function Get-RegistryBackupInfo {
    <#
    .SYNOPSIS
        Alle Angaben zu einer Sicherung; prüft Begleitdatei und Inhalt.
    .OUTPUTS
        SoftwareInventory.RegistryBackup. Problem ist $null, wenn die Sicherung zurückgespielt werden kann,
        sonst ein Code (Missing, Empty, ..., MetadataMissing, MetadataInvalid); ProblemMessage ist die Meldung dazu.
        Scope (User/Machine) folgt aus dem Ort der Datei; Elevated ist bei Machine gesetzt (Aktionen nur mit UAC über
        den Helfer, der alles erneut prüft). Expired: älter als 365 Tage (Änderungszeit der .reg).
    #>
    param([System.IO.FileInfo] $File)
    $fileScope = if ($File.PSObject.Properties['BackupScope'] -and $File.BackupScope -eq 'Machine') { 'Machine' } else { 'User' }
    $sidecar = Read-RegistryBackupSidecar -File $File.FullName
    $content = Get-RegistryBackupText -File $File.FullName
    if ($sidecar.Data) {
        $d = $sidecar.Data
        $name = $d.Name; $key = $d.NativeKey; $created = $d.CreatedAt; $reasons = @($d.Reasons)
        # Der Bereich aus der .json muss zum Ort passen (eine HKLM-Sicherung liegt nur im Admin-Ordner).
        $problem = if ($d.Scope -and $d.Scope -cne $fileScope) { 'MetadataInvalid' }
        elseif ($content.Problem) { $content.Problem }
        else { Test-RegistryBackupContent -Text $content.Text -NativeKey $key -Scope $fileScope }
    }
    else {
        $legacy = Get-LegacyBackupDetail -File $File -Text $content.Text
        $name = $legacy.Name; $key = $legacy.NativeKey; $created = $File.LastWriteTimeUtc; $reasons = @()
        $problem = $sidecar.Problem
    }
    $scope = $fileScope
    [pscustomobject] @{
        PSTypeName     = 'SoftwareInventory.RegistryBackup'
        Id             = Get-RegistryBackupId $File.Name
        Name           = $name
        CreatedAt      = $created
        NativeKey      = $key
        Scope          = $scope
        Elevated       = $scope -eq 'Machine'
        Expired        = [bool] (Test-RegistryBackupExpired -File $File)
        Reasons        = @($reasons | ForEach-Object { New-InventoryMessage $_.Code @($_.Args) })
        IsLegacy       = -not $sidecar.Data
        CanRestore     = -not $problem
        Problem        = $problem
        ProblemMessage = if ($problem) { New-InventoryMessage "Backup$problem" } else { $null }
        FileName       = $File.Name
        SizeBytes      = $File.Length
    }
}

function New-BackupActionPlan {
    # Gemeinsamer Plan für Restore-/Remove-RegistryBackup. CommandLine (wird bestätigt) ist die Sicherungs-ID und
    # der Schlüssel: Ändert sich die .json nach der Bestätigung, weicht sie ab und nichts wird ausgeführt.
    param([string] $Action, [string] $Name, [string] $BackupId, [string] $NativeKey, [string] $BackupFile, [string] $Method, [string] $Scope = 'User')
    $elevated = $Scope -eq 'Machine'
    [ordered]@{
        PSTypeName = 'SoftwareInventory.ActionPlan'; ActionId = [guid]::NewGuid().ToString(); Action = $Action; Name = $Name
        WingetId = $null; WingetSource = $null; RegistryKey = $NativeKey; ProductCode = $null; PackageFullName = $null
        Scope = $Scope; Method = $Method; FilePath = $null; Arguments = $null; CommandLine = (@($BackupId, $NativeKey) | Where-Object { $_ }) -join ' '
        Elevated = $elevated; RestorePoint = $false; Result = $null; Message = $null; NextMethod = $null; VendorUrl = $null
        BackupFile = $BackupFile; NativeKey = $NativeKey; BackupId = $BackupId
        HelperInWritableFolder = $(if ($elevated) { [bool] (Test-HelperInWritableFolder) } else { $false })
        State = [pscustomobject] @{ Present = $true; Version = $null }
    }
}

function Invoke-BackupHelper {
    <#
    .SYNOPSIS
        Führt eine Sicherungs-Operation des Helfers aus (UAC) und liefert dessen Felder über eine sichere Abfrage.
    .OUTPUTS
        @{ Status; Error; ErrorCode; Done; Deleted; NativeKey; LeftOver }; fehlende Felder sind $null (StrictMode).
    #>
    param([Parameter(Mandatory)] [hashtable] $HelperPlan)
    $HelperPlan['RestorePoint'] = $false
    $run = Start-ElevatedHelper -TimeoutSeconds 300 -HelperPlan $HelperPlan
    $field = { param($Name) if ($run -is [System.Collections.IDictionary] -and $run.Contains($Name)) { $run[$Name] } }
    @{
        Status = & $field 'Status'; Error = & $field 'Error'; ErrorCode = & $field 'ErrorCode'
        Done = (& $field 'Done') -is [bool] -and (& $field 'Done'); Deleted = & $field 'Deleted'
        NativeKey = & $field 'NativeKey'; LeftOver = & $field 'LeftOver'
    }
}

function Complete-BackupHelperResult {
    <#
    .SYNOPSIS
        Setzt Ergebnis und Meldung nach einer Sicherungs-Operation des Helfers. Erfolg nur mit Done ohne Fehler und wenn
        die eigene Prüfung danach ($Verified) zustimmt.
    #>
    param($Result, [hashtable] $Run, [bool] $Verified, $SuccessMessage)
    if ($Run.Status -eq 'ElevationDenied') {
        $Result.Result = 'ElevationDenied'
        $Result.Message = $Run.Error
    }
    elseif ($Run.Status -ne 'Completed' -or $Run.Error -or -not $Run.Done) {
        $Result.Result = 'Failed'
        $Result.Message = if ($Run.Error) { $Run.Error } else { New-InventoryMessage HelperResultUnreadable }
    }
    elseif (-not $Verified) {
        $Result.Result = 'Failed'
        $Result.Message = New-InventoryMessage BackupResultNotVerified
    }
    else {
        $Result.Result = 'Succeeded'
        $Result.Message = $SuccessMessage
    }
}

function Get-BackupActionInput {
    # Kennung aus einer Zeichenfolge oder einem Objekt von Get-RegistryBackup.
    param($Item)
    if ($Item -is [string]) { return $Item }
    [string] (Get-RecordValue $Item 'Id')
}
