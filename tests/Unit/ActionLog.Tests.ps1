BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

Describe 'Aktionsprotokoll' {
    BeforeEach {
        $appData = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Mock -ModuleName SoftwareInventory Get-AppDataDirectory { $appData }
        $logDir = Join-Path $appData 'logs\actions'

        function Write-TestEntry {
            param([string] $Id, [string] $Phase, [hashtable] $Data = @{})
            $all = @{ ActionId = $Id; Action = 'Uninstall'; Name = 'Contoso Tool'; Result = 'Succeeded' }
            foreach ($k in $Data.Keys) { $all[$k] = $Data[$k] }
            InModuleScope SoftwareInventory -Parameters @{ P = $Phase; D = $all } { Write-ActionLogEntry -Phase $P -Data $D }
        }
    }

    It 'schreibt eine JSON-Zeile pro Eintrag mit Zeitstempel, Benutzer und Phase' {
        Write-TestEntry -Id 'a1' -Phase Started
        Write-TestEntry -Id 'a1' -Phase Completed
        $file = Get-ChildItem $logDir -Filter '*.jsonl'
        $file.Name | Should -Match '^\d{4}-\d{2}-\d{2}\.jsonl$'
        $lines = Get-Content $file.FullName
        $lines.Count | Should -Be 2
        $first = $lines[0] | ConvertFrom-Json
        $first.Phase | Should -Be 'Started'
        $first.User | Should -Be ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
        $first.SchemaVersion | Should -Be 1
        $first.Timestamp | Should -Not -BeNullOrEmpty
    }

    It 'fasst Start und Abschluss zu einem Eintrag zusammen' {
        Write-TestEntry -Id 'a1' -Phase Started -Data @{ Result = $null }
        Write-TestEntry -Id 'a1' -Phase Completed -Data @{ Result = 'Succeeded'; VersionAfter = $null }
        $log = @(Get-ActionLog)
        $log.Count | Should -Be 1
        $log[0].Result | Should -Be 'Succeeded'
        $log[0].PSObject.TypeNames | Should -Contain 'SoftwareInventory.ActionLogEntry'
        $log[0].StartedAt | Should -BeOfType [datetime]
        $log[0].CompletedAt | Should -BeOfType [datetime]
    }

    It 'meldet Aktionen ohne Abschluss als Incomplete' {
        Write-TestEntry -Id 'b2' -Phase Started
        (Get-ActionLog).Result | Should -Be 'Incomplete'
    }

    It 'überspringt beschädigte und abgeschnittene Zeilen mit Warnung' {
        Write-TestEntry -Id 'c1' -Phase Completed
        $file = (Get-ChildItem $logDir -Filter '*.jsonl').FullName
        Add-Content -LiteralPath $file -Value '{"ActionId":"kaputt","Phase":"Compl'
        Add-Content -LiteralPath $file -Value 'kein json'
        Add-Content -LiteralPath $file -Value '{"ohne":"Pflichtfelder"}'
        Write-TestEntry -Id 'c2' -Phase Completed
        $log = @(Get-ActionLog -WarningVariable warnings -WarningAction SilentlyContinue)
        $log.ActionId | Should -Be @('c1', 'c2')
        $warnings | Should -Match '3 beschädigte'
    }

    It 'liefert ohne Protokoll nichts und wirft nicht' {
        { Get-ActionLog } | Should -Not -Throw
        Get-ActionLog | Should -BeNullOrEmpty
    }

    It 'filtert nach Name, Aktion, Ergebnis, Zeitraum und Anzahl' {
        Write-TestEntry -Id 'd1' -Phase Completed -Data @{ Name = '7-Zip'; Action = 'Update'; Result = 'Succeeded' }
        Write-TestEntry -Id 'd2' -Phase Completed -Data @{ Name = 'VLC'; Action = 'Uninstall'; Result = 'Failed' }
        Write-TestEntry -Id 'd3' -Phase Completed -Data @{ Name = 'VLC media player'; Action = 'Update'; Result = 'NotVerified' }
        (Get-ActionLog -Name 'VLC*').ActionId | Should -Be @('d2', 'd3')
        (Get-ActionLog -Action Update).ActionId | Should -Be @('d1', 'd3')
        (Get-ActionLog -Result Failed, NotVerified).ActionId | Should -Be @('d2', 'd3')
        (Get-ActionLog -Last 1).ActionId | Should -Be 'd3'
        Get-ActionLog -After (Get-Date).AddMinutes(5) | Should -BeNullOrEmpty
        @(Get-ActionLog -Before (Get-Date).AddMinutes(5)).Count | Should -Be 3
    }

    It 'schreibt keine API-Schlüssel ins Protokoll' {
        $env:NVD_API_KEY = 'geheim-1234567890'
        try {
            Write-TestEntry -Id 'e1' -Phase Completed -Data @{ Output = 'Fehler mit geheim-1234567890 im Text' }
            $raw = Get-Content (Get-ChildItem $logDir -Filter '*.jsonl').FullName -Raw
            $raw | Should -Not -Match 'geheim-1234567890'
        }
        finally {
            Remove-Item Env:\NVD_API_KEY
        }
    }

    It 'verträgt gleichzeitige Schreiber ohne vermischte Zeilen' {
        $module = (Get-Module SoftwareInventory).Path
        $jobs = 1..4 | ForEach-Object {
            Start-ThreadJob -ArgumentList $module, $appData, $_ -ScriptBlock {
                param($ModulePath, $Root, $N)
                Import-Module $ModulePath
                & (Get-Module SoftwareInventory) {
                    param($Root, $N)
                    function Get-AppDataDirectory { $Root }
                    1..25 | ForEach-Object { Write-ActionLogEntry -Phase Completed -Data @{ ActionId = "t$N-$_"; Name = 'x' * 500 } }
                } $Root $N
            }
        }
        $jobs | Wait-Job | Receive-Job
        $lines = Get-Content (Get-ChildItem $logDir -Filter '*.jsonl').FullName
        $lines.Count | Should -Be 100
        foreach ($l in $lines) { { $l | ConvertFrom-Json } | Should -Not -Throw }
    }
}

Describe 'Installer-Logs' {
    It 'löscht das Log nach Erfolg und hebt es bei Fehlern komprimiert auf' {
        $ok = Join-Path $TestDrive 'ok.log'
        $bad = Join-Path $TestDrive 'bad.log'
        Set-Content $ok 'MSI log' ; Set-Content $bad 'MSI log'
        InModuleScope SoftwareInventory -Parameters @{ P = $ok } { Complete-InstallerLog -Path $P -Keep $false } | Should -BeNullOrEmpty
        Test-Path $ok | Should -BeFalse
        $zip = InModuleScope SoftwareInventory -Parameters @{ P = $bad } { Complete-InstallerLog -Path $P -Keep $true }
        $zip | Should -BeLike '*bad.zip'
        Test-Path $zip | Should -BeTrue
        Test-Path $bad | Should -BeFalse
    }

    It 'packt das Log mit System.IO.Compression lesbar ein, ohne Compress-Archive, und ersetzt ein altes ZIP' {
        Mock -ModuleName SoftwareInventory Compress-Archive { throw 'darf nicht benutzt werden' }
        $log = Join-Path $TestDrive 'msi.log'
        Set-Content $log 'alter Inhalt'
        InModuleScope SoftwareInventory -Parameters @{ P = $log } { Complete-InstallerLog -Path $P -Keep $true } | Out-Null
        Set-Content $log "Zeile 1`nFehler 1603"
        $zip = InModuleScope SoftwareInventory -Parameters @{ P = $log } { Complete-InstallerLog -Path $P -Keep $true }

        $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
        try {
            $archive.Entries.Count | Should -Be 1
            $archive.Entries[0].Name | Should -Be 'msi.log'
            $reader = [System.IO.StreamReader]::new($archive.Entries[0].Open())
            try { $reader.ReadToEnd() | Should -Match 'Fehler 1603' } finally { $reader.Dispose() }
        }
        finally { $archive.Dispose() }
        Should -Invoke -ModuleName SoftwareInventory Compress-Archive -Times 0
    }
}

Describe 'Invoke-AppDataCleanup' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        function New-AgedFile {
            param([string] $RelativePath, [int] $AgeDays, [int] $SizeKB = 1)
            $path = Join-Path $root $RelativePath
            New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
            [System.IO.File]::WriteAllBytes($path, [byte[]]::new($SizeKB * 1KB))
            (Get-Item $path).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-$AgeDays)
            $path
        }
    }

    It 'löscht Dateien, die älter als die Aufbewahrungsfrist sind, und leere Ordner' {
        $old = New-AgedFile 'logs\actions\2026-01-01.jsonl' 40
        $oldCache = New-AgedFile 'cache\NVD\alt.json' 31
        $new = New-AgedFile 'logs\actions\2026-10-20.jsonl' 5
        $count = InModuleScope SoftwareInventory -Parameters @{ R = $root } { Invoke-AppDataCleanup -RetentionDays 30 -MaxSizeMB 100 -Root $R }
        $count | Should -Be 2
        Test-Path $old | Should -BeFalse
        Test-Path $oldCache | Should -BeFalse
        Test-Path $new | Should -BeTrue
        Test-Path (Join-Path $root 'cache\NVD') | Should -BeFalse
    }

    It 'löscht bei Überschreitung der Größe das Älteste zuerst' {
        $a = New-AgedFile 'cache\a.json' 10 600
        $b = New-AgedFile 'logs\installer\b.zip' 5 600
        $c = New-AgedFile 'logs\actions\c.jsonl' 1 600
        InModuleScope SoftwareInventory -Parameters @{ R = $root } { Invoke-AppDataCleanup -RetentionDays 30 -MaxSizeMB 1 -Root $R } | Should -Be 2
        Test-Path $a | Should -BeFalse
        Test-Path $b | Should -BeFalse
        Test-Path $c | Should -BeTrue
    }

    It 'lässt gespeicherte Scans unangetastet' {
        $scan = New-AgedFile 'scans\20250101-000000-000.json' 400 2000
        InModuleScope SoftwareInventory -Parameters @{ R = $root } { Invoke-AppDataCleanup -RetentionDays 1 -MaxSizeMB 1 -Root $R } | Should -Be 0
        Test-Path $scan | Should -BeTrue
    }

    It 'überspringt gesperrte Dateien ohne Fehler' {
        $locked = New-AgedFile 'logs\actions\offen.jsonl' 40
        $stream = [System.IO.File]::Open($locked, 'Open', 'Read', 'None')
        try {
            { InModuleScope SoftwareInventory -Parameters @{ R = $root } { Invoke-AppDataCleanup -RetentionDays 30 -Root $R } } | Should -Not -Throw
            Test-Path $locked | Should -BeTrue
        }
        finally {
            $stream.Dispose()
        }
    }

    It 'läuft ohne App-Ordner' {
        InModuleScope SoftwareInventory -Parameters @{ R = (Join-Path $TestDrive 'fehlt') } { Invoke-AppDataCleanup -Root $R } | Should -Be 0
    }
}
