BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-TestRecord {
        param([string] $Name, [string] $Version, [hashtable] $Property = @{})
        InModuleScope SoftwareInventory -Parameters @{ N = $Name; V = $Version; P = $Property } {
            $P.Version = $V
            New-SoftwareRecord -Name $N -Source Registry -Property $P
        }
    }
}

Describe 'Save-InventorySnapshot / Get-InventorySnapshot' {
    BeforeAll {
        $dir = Join-Path $TestDrive 'scans'
        $records = @(
            New-TestRecord 'Contoso Tool' '2.1' @{ RegistryKey = 'HKLM:\X\Contoso'; WingetId = 'Contoso.Tool' }
            New-TestRecord 'Fabrikam' '1.0'
        )
        $first = $records | Save-InventorySnapshot -Directory $dir
        $second = @() | Save-InventorySnapshot -Directory $dir
    }

    It 'schreibt eine JSON-Datei mit Schema und Zeitstempel' {
        $first.Name | Should -Match '^\d{8}-\d{6}-\d{3}\.json$'
        $json = Get-Content $first.FullName -Raw | ConvertFrom-Json
        $json.SchemaVersion | Should -Be 2
        $json.Records.Count | Should -Be 2
    }

    It 'lädt Snapshots neueste zuerst und stellt Datensätze wieder her' {
        $all = @(Get-InventorySnapshot -Directory $dir)
        $all.Count | Should -Be 2
        $all[0].Path | Should -Be $second.FullName
        $all[0].Count | Should -Be 0

        $loaded = Get-InventorySnapshot -LiteralPath $first.FullName
        $loaded.Records[0].PSObject.TypeNames[0] | Should -Be 'SoftwareInventory.SoftwareRecord'
        $loaded.Records[0].WingetId | Should -Be 'Contoso.Tool'
        $loaded.CreatedAt.Kind | Should -Be 'Utc'
    }

    It 'begrenzt mit -Latest' {
        @(Get-InventorySnapshot -Directory $dir -Latest 1).Count | Should -Be 1
    }

    It 'ergänzt bei Snapshots mit Schema 1 die neuen Felder' {
        $old = Join-Path $TestDrive 'v1.json'
        '{"SchemaVersion":1,"CreatedAt":"2026-10-24T10:00:00Z","Records":[{"Name":"Alt","Version":"1.0","Sources":["Registry"]}]}' | Set-Content $old
        $record = (Get-InventorySnapshot -LiteralPath $old).Records[0]
        $record.PSObject.Properties.Name | Should -Contain 'FilePath'
        $record.FilePath | Should -BeNullOrEmpty
        Compare-InventorySnapshot -Reference $record -Difference $record | Should -BeNullOrEmpty
    }

    It 'überspringt Snapshots mit neuerem Schema' {
        $future = Join-Path $TestDrive 'future.json'
        '{"SchemaVersion":99,"CreatedAt":"2030-01-01T00:00:00Z","Records":[]}' | Set-Content $future
        Get-InventorySnapshot -LiteralPath $future -WarningAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'Compare-InventorySnapshot' {
    It 'erkennt hinzugefügte, entfernte und geänderte Programme' {
        $old = @(
            New-TestRecord '7-Zip 26.04 (x64)' '26.04' @{ RegistryKey = 'HKLM:\X\7-zip' }
            New-TestRecord 'Altes Tool' '1.0' @{ RegistryKey = 'HKLM:\X\old' }
            New-TestRecord 'Firefox' '157.0' @{ PackageFamilyName = 'Mozilla.Firefox_n80' }
        )
        $new = @(
            New-TestRecord '7-Zip 26.05 (x64)' '26.05' @{ RegistryKey = 'HKLM:\X\7-zip' }
            New-TestRecord 'Firefox' '157.0' @{ PackageFamilyName = 'Mozilla.Firefox_n80' }
            New-TestRecord 'Neues Tool' '0.1' @{ WingetId = 'New.Tool' }
        )
        $changes = Compare-InventorySnapshot -Reference $old -Difference $new

        @($changes).Count | Should -Be 3
        $zip = $changes | Where-Object Change -eq 'VersionChanged'
        $zip.OldVersion | Should -Be '26.04'
        $zip.NewVersion | Should -Be '26.05'
        ($changes | Where-Object Change -eq 'Added').Name | Should -Be 'Neues Tool'
        ($changes | Where-Object Change -eq 'Removed').Name | Should -Be 'Altes Tool'
    }

    It 'vergleicht ohne Parameter die beiden neuesten Snapshots' {
        $dir = Join-Path $TestDrive 'cmp'
        @(New-TestRecord 'A' '1.0') | Save-InventorySnapshot -Directory $dir | Out-Null
        @(New-TestRecord 'A' '2.0') | Save-InventorySnapshot -Directory $dir | Out-Null
        Mock -ModuleName SoftwareInventory Get-DefaultSnapshotDirectory { $dir }

        $change = Compare-InventorySnapshot
        $change.Change | Should -Be 'VersionChanged'
        $change.NewVersion | Should -Be '2.0'
    }
}
