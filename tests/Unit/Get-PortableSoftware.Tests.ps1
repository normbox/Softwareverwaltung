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
        # Mocks sehen keine Closures; die Daten liegen daher auf Skriptebene der Testdatei.
        $script:ScenarioInfo = @{}
        foreach ($i in @($FileInfo) + @($TraceInfo)) { $script:ScenarioInfo[$i.Path] = $i }
        $script:ScenarioScan = if ($PSBoundParameters.ContainsKey('ScanFile')) { $ScanFile } else { @($FileInfo | ForEach-Object Path) }
        $script:ScenarioTrace = @($Trace | ForEach-Object {
                [pscustomobject] @{ Path = $_.Path; Evidence = $_.Evidence; LastRun = $null; RunCount = $null } })
        Mock -ModuleName SoftwareInventory Get-UserAssistTrace { $script:ScenarioTrace | Where-Object Evidence -eq 'UserAssist' }
        Mock -ModuleName SoftwareInventory Get-ProcessTrace { $script:ScenarioTrace | Where-Object Evidence -eq 'Process' }
        Mock -ModuleName SoftwareInventory Get-AutostartTrace { $script:ScenarioTrace | Where-Object Evidence -eq 'Autostart' }
        Mock -ModuleName SoftwareInventory Get-ScheduledTaskTrace { $script:ScenarioTrace | Where-Object Evidence -eq 'ScheduledTask' }
        Mock -ModuleName SoftwareInventory Test-Path { $PathType -eq 'Leaf' }
        # $TestDrive liegt selbst im echten %TEMP%; als Temp-Ordner gilt deshalb nur $TestDrive\Temp.
        Mock -ModuleName SoftwareInventory Get-TempDirectory { Join-Path $TestDrive 'Temp' }
        Mock -ModuleName SoftwareInventory Find-ExecutableFile { $script:ScenarioScan }
        Mock -ModuleName SoftwareInventory Get-ExecutableInfo { $script:ScenarioInfo[$Path] }
        $params = @{ Trace = 'UserAssist', 'Process', 'Autostart', 'ScheduledTask'; Path = $TestDrive; Inventory = $Inventory }
        foreach ($key in $Parameter.Keys) { $params[$key] = $Parameter[$key] }
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

    It 'ordnet Herstellerordner nur über gültig signierte Dateien zu (<Signature>)' -TestCases @(
        @{ Signature = 'Valid'; Expected = $true }
        @{ Signature = 'NotSigned'; Expected = $false }
        @{ Signature = 'HashMismatch'; Expected = $false }
        @{ Signature = $null; Expected = $false }
    ) {
        $info = New-Info "$env:ProgramData\Ubisoft\x\helper.exe" 'Helper' '1.0' -Signature $Signature -Company 'Ubisoft Entertainment'
        InModuleScope SoftwareInventory -Parameters @{ I = $info } {
            $publishers = [System.Collections.Generic.HashSet[string]]::new([string[]] @('ubisoft'))
            Test-InstalledProgramFile -Info $I -InstalledPublisher $publishers
        } | Should -Be $Expected
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
                New-Info "$tools\Python313\python.exe" 'Python' '3.13.15150.1013' -Company 'Python Software Foundation' -Signature 'Valid'
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

Describe 'Remove-InstalledMatch (Abgleich über Name und Version)' {
    BeforeAll {
        $python = New-InventoryRecord 'Python 3.13.15 (64-bit)' 'Python Software Foundation' '3.13.15150.0'
    }

    It 'blendet nie eine ganze Scan-Wurzel aus' {
        $root = Join-Path $TestDrive 'Tools'
        $files = @(
            New-Info "$root\python.exe" 'Python' '3.13.15150.1013' -Company 'Python Software Foundation' -Signature 'Valid'
            New-Info "$root\sub\tool.exe" $null $null -Company $null
        )
        $r = Invoke-PortableScenario -FileInfo $files -Inventory @($python) -Parameter @{ Path = $root; Trace = @() }
        $r.FilePath | Should -Not -Contain "$root\python.exe"
        # Ohne Produktname und Hersteller würde tool.exe sonst mit dem Ordner ausgeblendet.
        $r.FilePath | Should -Contain "$root\sub\tool.exe"
    }

    It 'behält im ausgeblendeten Ordner Dateien mit eigenem Produkt und anderem Hersteller' {
        $dir = Join-Path $TestDrive 'Apps\Python313'
        $files = @(
            New-Info "$dir\python.exe" 'Python' '3.13.15150.1013' -Company 'Python Software Foundation' -Signature 'Valid'
            New-Info "$dir\Scripts\pip.exe" $null $null -Company $null
            New-Info "$dir\Scripts\helper.exe" 'Python Helper' '3.13' -Company 'Python Software Foundation'
            New-Info "$dir\Scripts\miner.exe" 'Miner' '1.0' -Company 'Mallory Ltd'
        )
        $r = Invoke-PortableScenario -FileInfo $files -Inventory @($python)
        $r.FilePath | Should -Not -Contain "$dir\Scripts\pip.exe"
        $r.FilePath | Should -Not -Contain "$dir\Scripts\helper.exe"
        $r.FilePath | Should -Contain "$dir\Scripts\miner.exe"
    }

    It 'wertet eine unsignierte Datei mit Herstellerangabe nicht als Treffer' {
        $dir = Join-Path $TestDrive 'Apps\FakePython'
        $files = @(
            New-Info "$dir\python.exe" 'Python' '3.13.15150.1013' -Company 'Python Software Foundation' -Signature 'NotSigned'
            New-Info "$dir\Scripts\pip.exe" $null $null -Company $null
        )
        $r = Invoke-PortableScenario -FileInfo $files -Inventory @($python)
        $r.FilePath | Should -Contain "$dir\python.exe"
    }

    It 'wertet Dateien ohne Herstellerangabe wie bisher über Name und Version' {
        $dir = Join-Path $TestDrive 'Apps\WinUAE'
        $winuae = New-InventoryRecord 'WinUAE 64-bit 6.0.2' 'Arabuusimiehet' '6.0.2.0'
        $files = @(New-Info "$dir\winuae64.exe" 'WinUAE' '6.0.2.0' -Company $null -Signature 'NotSigned')
        $r = Invoke-PortableScenario -FileInfo $files -Inventory @($winuae)
        $r.FilePath | Should -Not -Contain "$dir\winuae64.exe"
    }
}

Describe 'Signierte Dateien in Temp' {
    It 'verwirft sie nur, wenn allein der Dateiscan sie fand (<Evidence>)' -TestCases @(
        @{ Evidence = 'FileScan'; Expected = $false }
        @{ Evidence = 'Process'; Expected = $true }
        @{ Evidence = 'UserAssist'; Expected = $true }
        @{ Evidence = 'Autostart'; Expected = $true }
        @{ Evidence = 'ScheduledTask'; Expected = $true }
    ) {
        $temp = Join-Path $TestDrive 'Temp'
        Mock -ModuleName SoftwareInventory Get-TempDirectory { $temp }
        $file = New-Info "$temp\signed.exe" 'Signed Tool' '1.0' -Signature 'Valid'
        $r = if ($Evidence -eq 'FileScan') {
            Invoke-PortableScenario -FileInfo @($file) -Parameter @{ IncludeTemp = $true }
        }
        else {
            Invoke-PortableScenario -FileInfo @() -TraceInfo @($file) -Trace @(@{ Path = $file.Path; Evidence = $Evidence }) -Parameter @{ IncludeTemp = $true }
        }
        ($r.FilePath -contains $file.Path) | Should -Be $Expected
    }
}

Describe 'Merge-NestedComponent (Bestandteile eines Programms)' {
    It 'zieht keine Dateien unter ein Programm, das direkt in einer Scan-Wurzel liegt' {
        $root = Join-Path $TestDrive 'Tools'
        $files = @(
            New-Info "$root\putty.exe" 'PuTTY' '0.70' -Company 'Simon Tatham'
            New-Info "$root\other\nmap.exe" 'Nmap' '7.0' -Company 'Insecure.Com'
        )
        $r = Invoke-PortableScenario -FileInfo $files -Parameter @{ Path = $root; Trace = @() }
        $r.FilePath | Should -Contain "$root\putty.exe"
        $r.FilePath | Should -Contain "$root\other\nmap.exe"
    }

    It 'übernimmt die Warnsignale der Unterdateien in das Programm' {
        $app = Join-Path $TestDrive 'Apps\Contoso'
        $files = @(
            New-Info "$app\app.exe" 'Contoso App' '2.0' -Signature 'Valid' -Length 5000
            New-Info "$app\resources\helper.exe" 'Helper' '1.0' -Signature 'HashMismatch'
        )
        $r = @(Invoke-PortableScenario -FileInfo $files -Trace @(@{ Path = "$app\resources\helper.exe"; Evidence = 'Autostart' }))
        $r.Count | Should -Be 1
        $r[0].FilePath | Should -Be "$app\app.exe"
        $r[0].Flags | Should -Contain 'InvalidSignature'
        $r[0].Flags | Should -Contain 'Autostart'
        $r[0].Evidence | Should -Contain 'Autostart'
    }
}

Describe 'Dokumentation der festen Ausschlüsse' {
    It 'nennt jeden festen Ausschluss aus Get-ScanExclusion in docs/INVENTAR-SCHEMA.md' {
        $doc = Get-Content "$PSScriptRoot/../../docs/INVENTAR-SCHEMA.md" -Raw
        $section = ($doc -split '## Portable Programme: Suche und Ausschlüsse')[1] -split '\n## ' | Select-Object -First 1
        $expected = @(
            '%windir%', '%ProgramFiles%\WindowsApps', 'ProgramData\Microsoft', 'ProgramData\Package Cache',
            '%LOCALAPPDATA%\Packages', '%LOCALAPPDATA%\Microsoft\WindowsApps', '%LOCALAPPDATA%\*-updater',
            '$Recycle.Bin', 'System Volume Information', 'Windows.old', '$WinREAgent', '$SysReset',
            'WindowsApps', 'WpSystem', 'XboxGames', 'C:\Windows\Temp'
        )
        foreach ($e in $expected) { $section | Should -BeLike "*$e*" -Because "der Ausschluss '$e' dokumentiert sein muss" }

        # Gegenprobe: Die Namen pro Laufwerk im Code stimmen mit der Liste überein.
        $code = Get-Content "$PSScriptRoot/../../src/SoftwareInventory/Private/Find-ExecutableFile.ps1" -Raw
        $line = ($code -split '\n' | Where-Object { $_ -match "foreach \(\`$name in '\`$Recycle" })
        $line | Should -Not -BeNullOrEmpty
        foreach ($name in [regex]::Matches($line, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }) {
            $section | Should -BeLike "*$name*"
        }
    }
}

Describe 'Eigene Ausschlüsse und SmartExclusions' {
    BeforeAll {
        $python = New-InventoryRecord 'Python 3.13.15 (64-bit)' 'Python Software Foundation' '3.13.15150.0'
        $ubisoft = New-InventoryRecord 'Ubisoft Connect' 'Ubisoft' '174.2'
    }

    It 'betritt eigene Ausschlüsse weder beim Dateiscan noch bei Spuren' {
        $skip = Join-Path $TestDrive 'Builds'
        $files = @(New-Info "$TestDrive\keep\tool.exe" 'Tool' '1.0')
        $traced = New-Info "$skip\agent.exe" 'Agent' '1.0'
        $r = Invoke-PortableScenario -FileInfo $files -TraceInfo @($traced) -Trace @(@{ Path = $traced.Path; Evidence = 'Process' }) `
            -Parameter @{ ExcludePath = @('%TEMP%\gibt-es-nicht', $skip) }
        $r.FilePath | Should -Contain "$TestDrive\keep\tool.exe"
        $r.FilePath | Should -Not -Contain $traced.Path
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 1 -Exactly -ParameterFilter { $ExcludeDirectory -contains $skip }
    }

    It 'übernimmt eigene Ausschlüsse aus den Einstellungen, auch bei expliziten Parametern' {
        $skip = Join-Path $TestDrive 'FromSettings'
        Mock -ModuleName SoftwareInventory Read-InventorySetting {
            $s = InModuleScope SoftwareInventory { New-DefaultSetting }
            $s.FileScan.ExcludePaths = [string[]] @($skip)
            $s
        }
        $traced = New-Info "$skip\agent.exe" 'Agent' '1.0'
        $r = Invoke-PortableScenario -FileInfo @() -TraceInfo @($traced) -Trace @(@{ Path = $traced.Path; Evidence = 'Autostart' })
        $r.FilePath | Should -Not -Contain $traced.Path
    }

    It 'zeigt mit -NoSmartExclusion auch Herstellerordner und Abgleichstreffer' {
        $vendor = "$env:ProgramData\Ubisoft\Launcher\upc.exe"
        $files = @(
            New-Info "$TestDrive\Apps\Python313\python.exe" 'Python' '3.13.15150.1013' -Company 'Python Software Foundation' -Signature 'Valid'
            New-Info $vendor 'Ubisoft Connect' '174.2.0' -Company 'Ubisoft Entertainment' -Signature 'Valid'
        )
        $with = Invoke-PortableScenario -FileInfo $files -Inventory @($python, $ubisoft)
        $with.FilePath | Should -Not -Contain $vendor
        $with.FilePath | Should -Not -Contain "$TestDrive\Apps\Python313\python.exe"

        $without = Invoke-PortableScenario -FileInfo $files -Inventory @($python, $ubisoft) -Parameter @{ NoSmartExclusion = $true }
        $without.FilePath | Should -Contain $vendor
        $without.FilePath | Should -Contain "$TestDrive\Apps\Python313\python.exe"
    }

    It 'lässt Ordner aus InstallLocation auch ohne SmartExclusions aus' {
        $dir = Join-Path $TestDrive 'Apps\Contoso'
        $record = New-InventoryRecord 'Contoso' 'Contoso' '1.0' -InstallLocation $dir
        $traced = New-Info "$dir\contoso.exe" 'Contoso' '1.0'
        $r = Invoke-PortableScenario -FileInfo @() -TraceInfo @($traced) -Trace @(@{ Path = $traced.Path; Evidence = 'Process' }) `
            -Inventory @($record) -Parameter @{ NoSmartExclusion = $true }
        $r.FilePath | Should -Not -Contain $traced.Path
    }

    It 'übernimmt SmartExclusions = aus aus den Einstellungen' {
        Mock -ModuleName SoftwareInventory Read-InventorySetting {
            $s = InModuleScope SoftwareInventory { New-DefaultSetting }
            $s.FileScan.SmartExclusions = $false
            $s
        }
        $files = @(New-Info "$TestDrive\Apps\Python313\python.exe" 'Python' '3.13.15150.1013' -Company 'Python Software Foundation' -Signature 'Valid')
        $r = Invoke-PortableScenario -FileInfo $files -Inventory @($python)
        $r.FilePath | Should -Contain "$TestDrive\Apps\Python313\python.exe"
    }
}

Describe 'Spuren aus beschreibbaren Windows-Unterordnern' {
    It 'meldet <Evidence> aus <Folder> immer, auch ohne IncludeTemp' -TestCases @(
        @{ Evidence = 'Process'; Folder = 'Temp' }
        @{ Evidence = 'Autostart'; Folder = 'Tasks' }
        @{ Evidence = 'ScheduledTask'; Folder = 'Tracing' }
    ) {
        $file = New-Info "$env:windir\$Folder\dropper.exe" 'Dropper' '1.0' -Signature 'Valid'
        $r = Invoke-PortableScenario -FileInfo @() -TraceInfo @($file) -Trace @(@{ Path = $file.Path; Evidence = $Evidence })
        $r.FilePath | Should -Contain $file.Path
    }

    It 'meldet keine Spuren aus dem übrigen Windows-Ordner und keine UserAssist-Spur aus Windows\Temp' {
        $system = New-Info "$env:windir\System32\svchost.exe" 'Windows' '10.0' -Signature 'Valid'
        $ua = New-Info "$env:windir\Temp\viewer.exe" 'Viewer' '1.0'
        $r = Invoke-PortableScenario -FileInfo @() -TraceInfo @($system, $ua) -Trace @(
            @{ Path = $system.Path; Evidence = 'Process' }
            @{ Path = $ua.Path; Evidence = 'UserAssist' }
        )
        $r | Should -BeNullOrEmpty
    }

    It 'betritt den Windows-Ordner im Dateiscan weiterhin nicht' {
        Invoke-PortableScenario -FileInfo @() -Parameter @{ Drive = 'C'; Path = @(); IncludeTemp = $true } | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 1 -Exactly -ParameterFilter { $ExcludeDirectory -contains $env:windir }
    }

    It 'beachtet eigene Ausschlüsse auch hier' {
        $file = New-Info "$env:windir\Temp\agent.exe" 'Agent' '1.0'
        $r = Invoke-PortableScenario -FileInfo @() -TraceInfo @($file) -Trace @(@{ Path = $file.Path; Evidence = 'Process' }) `
            -Parameter @{ ExcludePath = @("$env:windir\Temp") }
        $r | Should -BeNullOrEmpty
    }
}
