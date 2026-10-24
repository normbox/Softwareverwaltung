BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-Info {
        param([string] $Path, [string] $Name, [string] $Version, [string] $Signature = 'NotSigned', [long] $Length = 1000, [string] $Company = 'Contoso')
        [pscustomobject] @{
            Path = $Path; Directory = Split-Path -Parent $Path; Length = $Length; Name = $Name; Description = $null
            Company = $Company; Version = $Version; Sha256 = $null; SignatureStatus = $Signature; Signer = $null; Machine = 'X64'
        }
    }

    function New-InventoryRecord {
        param([string] $Name, [string] $Publisher, [string] $Version, [string] $InstallLocation)
        InModuleScope SoftwareInventory -Parameters @{ N = $Name; P = $Publisher; V = $Version; L = $InstallLocation } {
            New-SoftwareRecord -Name $N -Source Registry -Property @{ Publisher = $P; Version = $V; InstallLocation = $L }
        }
    }

    function Invoke-PortableScenario {
        <#
            Führt Get-PortableSoftware mit erfundenen Dateien aus. FileScan liefert alle Dateien aus
            $FileInfo (ohne Spur); $Trace ist eine Liste von @{ Path; Evidence }.
            Muss innerhalb eines It-Blocks aufgerufen werden (dort gelten die Mocks).
        #>
        param([object[]] $FileInfo, [object[]] $TraceInfo = @(), [hashtable[]] $Trace = @(), [object[]] $Inventory = @(),
            [hashtable] $Parameter = @{}, [string[]] $ScanFile)
        $all = @{}
        foreach ($i in @($FileInfo) + @($TraceInfo)) { $all[$i.Path] = $i }
        $scan = if ($PSBoundParameters.ContainsKey('ScanFile')) { $ScanFile } else { @($FileInfo | ForEach-Object Path) }
        foreach ($name in 'UserAssist', 'Process', 'Autostart', 'ScheduledTask') {
            $hits = @($Trace | Where-Object { $_.Evidence -eq $name } | ForEach-Object {
                    [pscustomobject] @{ Path = $_.Path; Evidence = $_.Evidence; LastRun = $null; RunCount = $null } })
            Mock -ModuleName SoftwareInventory "Get-${name}Trace" { $hits }.GetNewClosure()
        }
        Mock -ModuleName SoftwareInventory Test-Path { $PathType -eq 'Leaf' }
        Mock -ModuleName SoftwareInventory Find-ExecutableFile { $scan }.GetNewClosure()
        Mock -ModuleName SoftwareInventory Get-ExecutableInfo { $all[$Path] }.GetNewClosure()
        $params = @{ Trace = 'UserAssist', 'Process', 'Autostart', 'ScheduledTask'; Path = $TestDrive; Inventory = $Inventory } + $Parameter
        @(Get-PortableSoftware @params -WarningAction SilentlyContinue)
    }
}

Describe 'Ausführungsspuren' {
    It 'dekodiert ROT13' {
        InModuleScope SoftwareInventory { ConvertFrom-Rot13 'P:\Gbbyf\chggl.rkr' } | Should -Be 'C:\Tools\putty.exe'
    }

    It 'liest Startanzahl und letzten Start aus UserAssist-Daten' {
        $data = [byte[]]::new(72)
        [BitConverter]::GetBytes([int] 7).CopyTo($data, 4)
        [BitConverter]::GetBytes([datetime]::new(2026, 10, 1, 12, 0, 0, [DateTimeKind]::Utc).ToFileTimeUtc()).CopyTo($data, 60)
        $info = InModuleScope SoftwareInventory -Parameters @{ D = $data } { ConvertFrom-UserAssistData $D }
        $info.RunCount | Should -Be 7
        $info.LastRun | Should -Be '2026-10-01T12:00:00.0000000Z'
    }

    It 'löst Known-Folder-IDs auf und verwirft Nicht-Pfade' {
        InModuleScope SoftwareInventory {
            $map = @{ '{374DE290-123F-4565-9164-39C4925E467B}' = 'C:\Users\x\Downloads' }
            Resolve-KnownFolderPath '{374de290-123f-4565-9164-39c4925e467b}\tool.exe' $map | Should -Be 'C:\Users\x\Downloads\tool.exe'
            Resolve-KnownFolderPath 'D:\Games\game.exe' $map | Should -Be 'D:\Games\game.exe'
            Resolve-KnownFolderPath 'Microsoft.Windows.Explorer' $map | Should -BeNullOrEmpty
        }
    }

    It 'liest UserAssist aus der Registry' {
        $key = New-Item -Path 'TestRegistry:\UA\Count' -Force
        $data = [byte[]]::new(72)
        [BitConverter]::GetBytes([int] 3).CopyTo($data, 4)
        New-ItemProperty -Path $key.PSPath -Name 'P:\Gbbyf\chggl.rkr' -Value $data -PropertyType Binary | Out-Null
        New-ItemProperty -Path $key.PSPath -Name 'HRZR_PGYFRFFVBA' -Value ([byte[]]::new(16)) -PropertyType Binary | Out-Null

        $trace = @(InModuleScope SoftwareInventory { Get-UserAssistTrace -Path 'TestRegistry:\UA\Count' })
        $trace.Count | Should -Be 1
        $trace[0].Path | Should -Be 'C:\Tools\putty.exe'
        $trace[0].RunCount | Should -Be 3
    }

    It 'ermittelt die .exe aus Befehlszeilen' -TestCases @(
        @{ Line = '"C:\Program Files\App\app.exe" --minimized'; Expected = 'C:\Program Files\App\app.exe' }
        @{ Line = 'C:\Tools\tool.exe /silent'; Expected = 'C:\Tools\tool.exe' }
        @{ Line = 'C:\Program Files\App\app.exe -x'; Expected = 'C:\Program Files\App\app.exe' }
        @{ Line = 'rundll32.exe shell32.dll'; Expected = $null }
        @{ Line = ''; Expected = $null }
    ) {
        InModuleScope SoftwareInventory -Parameters @{ L = $Line } { ConvertFrom-CommandLine $L } | Should -Be $Expected
    }
}

Describe 'Dateiscan und Ausschlüsse' {
    It 'findet .exe-Dateien und betritt ausgeschlossene Ordner nicht' {
        New-Item -ItemType Directory "$TestDrive\scan\a\b", "$TestDrive\scan\skip" -Force | Out-Null
        'x' | Set-Content "$TestDrive\scan\top.exe", "$TestDrive\scan\a\b\deep.exe", "$TestDrive\scan\skip\hidden.exe", "$TestDrive\scan\a\note.txt"

        $files = InModuleScope SoftwareInventory -Parameters @{ Root = "$TestDrive\scan" } {
            Find-ExecutableFile -Root $Root -ExcludeDirectory "$Root\skip"
        }
        $files | ForEach-Object { Split-Path -Leaf $_ } | Sort-Object | Should -Be @('deep.exe', 'top.exe')
    }

    It 'lehnt zu breite Installationsordner ab' -TestCases @(
        @{ Path = 'C:\'; Expected = $false }
        @{ Path = $env:ProgramFiles; Expected = $false }
        @{ Path = "$env:ProgramFiles\"; Expected = $false }
        @{ Path = $env:LOCALAPPDATA; Expected = $false }
        @{ Path = 'D:\Steam'; Expected = $true }
        @{ Path = "$env:ProgramFiles\7-Zip\"; Expected = $true }
        @{ Path = 'relativ\pfad'; Expected = $false }
    ) {
        InModuleScope SoftwareInventory -Parameters @{ P = $Path } { Test-SpecificInstallDirectory $P } | Should -Be $Expected
    }

    It 'behandelt auch Sammelordner und Common Files als zu breit: <Name>' -TestCases @(
        @{ Name = 'Desktop'; Path = [Environment]::GetFolderPath('Desktop') }
        @{ Name = 'Dokumente'; Path = [Environment]::GetFolderPath('MyDocuments') }
        @{ Name = 'Downloads'; Path = 'DOWNLOADS' }
        @{ Name = 'Temp'; Path = $env:TEMP }
        @{ Name = 'CommonProgramFiles'; Path = $env:CommonProgramFiles }
        @{ Name = 'CommonProgramFiles(x86)'; Path = ${env:CommonProgramFiles(x86)} }
    ) {
        InModuleScope SoftwareInventory -Parameters @{ P = $Path } {
            if ($P -eq 'DOWNLOADS') { $P = (Get-KnownFolderMap)['{374DE290-123F-4565-9164-39C4925E467B}'] }
            Test-SpecificInstallDirectory "$P\" | Should -BeFalse
            Test-SpecificInstallDirectory "$P\Contoso" | Should -BeTrue
        }
    }

    It 'ermittelt den Herstellerordner unter Program Files und ProgramData' -TestCases @(
        @{ Path = "$env:ProgramFiles\Brother\iPrint\x.exe"; Expected = "$env:ProgramFiles\Brother" }
        @{ Path = "$env:CommonProgramFiles\Acronis\Schedule2\s.exe"; Expected = "$env:CommonProgramFiles\Acronis" }
        @{ Path = "$env:ProgramData\Ubisoft\a\b.exe"; Expected = "$env:ProgramData\Ubisoft" }
        @{ Path = "$env:ProgramFiles\loose.exe"; Expected = $null }
        @{ Path = 'D:\Tools\x.exe'; Expected = $null }
    ) {
        InModuleScope SoftwareInventory -Parameters @{ P = $Path } { Get-VendorDirectory $P } | Should -Be $Expected
    }

    It 'normalisiert Versionen auf drei Teile' -TestCases @(
        @{ Version = '26.05'; Expected = '26.5.0' }
        @{ Version = '3.13.15150.1013'; Expected = '3.13.15150' }
        @{ Version = '1.2.3 (beta)'; Expected = '1.2.3' }
        @{ Version = 'unbekannt'; Expected = $null }
    ) {
        InModuleScope SoftwareInventory -Parameters @{ V = $Version } { Get-VersionPrefix $V } | Should -Be $Expected
    }
}

Describe 'Get-PortableSoftware' {
    BeforeAll {
        $tools = Join-Path $TestDrive 'Tools'
        $temp = Join-Path $TestDrive 'Temp'

        $infos = @{}
        foreach ($i in @(
                New-Info "$tools\App\app.exe" 'Contoso App' '2.0' -Length 5000
                New-Info "$tools\App\resources\helper.exe" 'Helper' '1.0'
                New-Info "$tools\Old\app.exe" 'Contoso App' '1.0' -Length 5000
                New-Info "$tools\CopyA\tool.exe" 'Tool' '3.0'
                New-Info "$tools\CopyB\tool.exe" 'Tool' '3.0'
                New-Info "$tools\Python313\python.exe" 'Python' '3.13.15150.1013' -Company 'Python Software Foundation'
                New-Info "$tools\Python313\Scripts\pip.exe" $null $null -Company $null
                New-Info "$temp\setup_signed.exe" 'Setup' '1.0' -Signature 'Valid'
                New-Info "$temp\dropper.exe" 'Dropper' '0.1'
            )) { $infos[$i.Path] = $i }

        Mock -ModuleName SoftwareInventory Get-UserAssistTrace { }
        Mock -ModuleName SoftwareInventory Get-ProcessTrace { }
        Mock -ModuleName SoftwareInventory Get-AutostartTrace {
            [pscustomobject] @{ Path = "$tools\CopyB\tool.exe"; Evidence = 'Autostart'; LastRun = $null; RunCount = $null }
        }
        Mock -ModuleName SoftwareInventory Get-ScheduledTaskTrace { }
        # Spuren gelten als vorhandene Dateien; alles andere (z. B. die Einstellungsdatei) als nicht vorhanden.
        Mock -ModuleName SoftwareInventory Test-Path { $PathType -eq 'Leaf' }
        Mock -ModuleName SoftwareInventory Find-ExecutableFile { $infos.Keys }
        Mock -ModuleName SoftwareInventory Get-ExecutableInfo { $infos[$Path] }
        Mock -ModuleName SoftwareInventory Get-TempDirectory { $temp }

        $inventory = @(InModuleScope SoftwareInventory {
                New-SoftwareRecord -Name 'Python 3.13.15 (64-bit)' -Source Registry -Property @{ Publisher = 'Python Software Foundation'; Version = '3.13.15150.0' }
            })
        $result = @(Get-PortableSoftware -Trace UserAssist, Process, Autostart, ScheduledTask -Drive C -IncludeTemp -Inventory $inventory)
    }

    It 'ordnet Dateien in Unterordnern dem Programm zu' {
        $app = $result | Where-Object FilePath -eq "$tools\App\app.exe"
        $app | Should -Not -BeNullOrEmpty
        $result.FilePath | Should -Not -Contain "$tools\App\resources\helper.exe"
    }

    It 'fasst identische Kopien zusammen und bevorzugt die mit Spuren' {
        $tool = @($result | Where-Object Name -eq 'Tool')
        $tool.Count | Should -Be 1
        $tool[0].FilePath | Should -Be "$tools\CopyB\tool.exe"
        $tool[0].CopyPaths | Should -Be @("$tools\CopyA\tool.exe")
        $tool[0].Flags | Should -Contain 'Autostart'
    }

    It 'markiert mehrere Versionen desselben Programms' {
        $apps = @($result | Where-Object Name -eq 'Contoso App')
        $apps.Count | Should -Be 2
        $apps | ForEach-Object { $_.Flags | Should -Contain 'MultipleVersions' }
    }

    It 'lässt installierte Programme ohne Pfad im Registry-Eintrag samt Unterordnern aus' {
        $result.FilePath | Should -Not -Contain "$tools\Python313\python.exe"
        $result.FilePath | Should -Not -Contain "$tools\Python313\Scripts\pip.exe"
    }

    It 'meldet aus Temp nur unsignierte Dateien' {
        $result.FilePath | Should -Not -Contain "$temp\setup_signed.exe"
        $dropper = $result | Where-Object FilePath -eq "$temp\dropper.exe"
        $dropper.Flags | Should -Contain 'Unsigned'
        $dropper.Flags | Should -Contain 'InDownloadsOrTemp'
    }

    It 'liefert Datensätze ohne Hilfsfelder' {
        $result | ForEach-Object {
            $_.InstallType | Should -Be 'Portable'
            $_.Sources | Should -Be @('Portable')
            $_.PSObject.Properties.Name | Should -Not -Contain 'CopyKey'
            $_.PSObject.Properties.Name | Should -Not -Contain 'HasProductName'
        }
    }

    It 'lehnt ungültige Laufwerksangaben ab' {
        { Get-PortableSoftware -Drive 'C:\Windows' -Inventory @() } | Should -Throw '*Laufwerksangabe*'
    }

    It 'scannt nichts und warnt, wenn nichts aktiviert ist' {
        Mock -ModuleName SoftwareInventory Get-SettingsPath { Join-Path $TestDrive 'none\settings.json' }
        $r = Get-PortableSoftware -Inventory @() -WarningVariable w -WarningAction SilentlyContinue
        $r | Should -BeNullOrEmpty
        "$w" | Should -Match 'Keine Nutzungsspuren'
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 0 -Exactly
    }
}
