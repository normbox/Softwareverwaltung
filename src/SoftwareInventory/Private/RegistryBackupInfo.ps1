# Angaben zu einer Sicherung (Get-RegistryBackup) und gemeinsame Teile von Restore-/Remove-RegistryBackup.

function Find-RegistryBackupFile {
    # Sucht die Sicherung anhand ihrer Kennung (GUID) im Sicherungsordner. Nie ein Pfad vom Aufrufer.
    param([string] $Id)
    $guid = [guid]::Empty
    if (-not [guid]::TryParseExact($Id, 'D', [ref] $guid)) { return $null }
    $directory = Get-RegistryBackupDirectory
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return $null }
    Get-ChildItem -LiteralPath $directory -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -ieq '.reg' -and (Get-RegistryBackupId $_.Name) -eq $guid.ToString() } |
        Select-Object -First 1
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
    #>
    param([System.IO.FileInfo] $File)
    $sidecar = Read-RegistryBackupSidecar -File $File.FullName
    $content = Get-RegistryBackupText -File $File.FullName
    if ($sidecar.Data) {
        $d = $sidecar.Data
        $name = $d.Name; $key = $d.NativeKey; $scope = $d.Scope; $created = $d.CreatedAt; $reasons = @($d.Reasons)
        $problem = if ($content.Problem) { $content.Problem } else { Test-RegistryBackupContent -Text $content.Text -NativeKey $key }
    }
    else {
        $legacy = Get-LegacyBackupDetail -File $File -Text $content.Text
        $name = $legacy.Name; $key = $legacy.NativeKey; $scope = $null; $created = $File.LastWriteTimeUtc; $reasons = @()
        $problem = $sidecar.Problem
    }
    [pscustomobject] @{
        PSTypeName     = 'SoftwareInventory.RegistryBackup'
        Id             = Get-RegistryBackupId $File.Name
        Name           = $name
        CreatedAt      = $created
        NativeKey      = $key
        Scope          = $scope
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
    # Gemeinsamer Plan für Restore-/Remove-RegistryBackup. CommandLine ist die Sicherungs-ID (wird bestätigt).
    param([string] $Action, [string] $Name, [string] $BackupId, [string] $NativeKey, [string] $BackupFile, [string] $Method)
    [ordered]@{
        PSTypeName = 'SoftwareInventory.ActionPlan'; ActionId = [guid]::NewGuid().ToString(); Action = $Action; Name = $Name
        WingetId = $null; WingetSource = $null; RegistryKey = $NativeKey; ProductCode = $null; PackageFullName = $null
        Scope = 'User'; Method = $Method; FilePath = $null; Arguments = $null; CommandLine = $BackupId
        Elevated = $false; RestorePoint = $false; Result = $null; Message = $null; NextMethod = $null; VendorUrl = $null
        BackupFile = $BackupFile; NativeKey = $NativeKey; BackupId = $BackupId
        State = [pscustomobject] @{ Present = $true; Version = $null }
    }
}

function Get-BackupActionInput {
    # Kennung aus einer Zeichenfolge oder einem Objekt von Get-RegistryBackup.
    param($Item)
    if ($Item -is [string]) { return $Item }
    [string] (Get-RecordValue $Item 'Id')
}
