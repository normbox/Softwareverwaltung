BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-TestRecord {
        param([hashtable] $Property = @{}, [string] $Name = 'Contoso Tool')
        InModuleScope SoftwareInventory -Parameters @{ N = $Name; P = $Property } { New-SoftwareRecord -Name $N -Source Registry -Property $P }
    }

    function New-TestFolder {
        # Ordner mit den angegebenen Dateien im Testlaufwerk
        param([string] $Name, [string[]] $File = @())
        $dir = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        foreach ($f in $File) { Set-Content -LiteralPath (Join-Path $dir $f) -Value 'x' }
        $dir
    }
}

Describe 'Resolve-InstallLocation' {
    BeforeEach {
        # Der Testordner liegt in Temp; als Zwischenspeicher gilt hier nur der eigene Cache-Ordner.
        $script:cache = New-TestFolder 'Windows\Installer' @('icon.exe')
        Mock -ModuleName SoftwareInventory Get-InstallerCacheRoot { $script:cache }
        Mock -ModuleName SoftwareInventory Get-MsiComponentPath { }
    }

    It 'nimmt InstallLocation aus dem Installer-Eintrag als sicher' {
        $dir = New-TestFolder 'App1'
        $r = New-TestRecord @{ InstallLocation = $dir } | Resolve-InstallLocation
        $r.Path | Should -Be $dir
        $r.Source | Should -Be 'InstallerEntry'
        $r.Certain | Should -BeTrue
        $r.Note.Code | Should -Be 'InstallLocationFromInstallerEntry'
        $r.Note.Text | Should -Be 'laut Installer-Eintrag'
        $r.CanOpen | Should -BeTrue
    }

    It 'leitet den Ordner aus dem Programmsymbol ab und kennzeichnet ihn als vermutlich' {
        $dir = New-TestFolder 'App2' @('app.exe')
        $r = New-TestRecord @{ DisplayIcon = (Join-Path $dir 'app.exe') } | Resolve-InstallLocation
        $r.Path | Should -Be $dir
        $r.Source | Should -Be 'DisplayIcon'
        $r.Certain | Should -BeFalse
        $r.Note.Text | Should -Match '^vermutlich'
    }

    It 'sucht weiter, wenn der Ordner aus dem Installer-Eintrag fehlt' {
        $dir = New-TestFolder 'App3' @('app.exe')
        $r = New-TestRecord @{ InstallLocation = (Join-Path $TestDrive 'gibt-es-nicht'); DisplayIcon = (Join-Path $dir 'app.exe') } | Resolve-InstallLocation
        $r.Source | Should -Be 'DisplayIcon'
    }

    It 'nennt LocationNotFound mit dem Pfad aus dem Eintrag, wenn keine Quelle etwas findet' {
        $missing = Join-Path $TestDrive 'gibt-es-nicht'
        $r = New-TestRecord @{ InstallLocation = $missing } | Resolve-InstallLocation
        $r.Path | Should -BeNullOrEmpty
        $r.Reason.Code | Should -Be 'LocationNotFound'
        $r.Reason.Args | Should -Be @($missing)
        $r.CanOpen | Should -BeFalse
    }

    It 'verwendet nie Zwischenspeicher des Installers' {
        $r = New-TestRecord @{ DisplayIcon = (Join-Path $script:cache 'icon.exe') } | Resolve-InstallLocation
        $r.Path | Should -BeNullOrEmpty
        $r.Reason.Code | Should -Be 'LocationOnlyInstallerCache'
    }

    It 'erkennt Symbol-Zwischenspeicher je Benutzer und von InstallShield' {
        InModuleScope SoftwareInventory {
            Test-InstallerCachePath 'C:\Users\x\AppData\Roaming\Microsoft\Installer\{11111111-2222-3333-4444-555555555555}' | Should -BeTrue
            Test-InstallerCachePath 'C:\Program Files (x86)\InstallShield Installation Information\{93795eb8}' | Should -BeTrue
            Test-InstallerCachePath 'C:\Program Files\Contoso' | Should -BeFalse
        }
    }

    It 'zählt einen abgeleiteten Ordner nur, wenn dort ein Programm liegt, nicht nur ein Deinstallationsprogramm' {
        $only = New-TestFolder 'App4' @('unins000.exe', 'readme.txt')
        $r = New-TestRecord @{ UninstallString = "`"$(Join-Path $only 'unins000.exe')`" /SILENT" } | Resolve-InstallLocation
        $r.Path | Should -BeNullOrEmpty
        $r.Reason.Code | Should -Be 'LocationNoProgramExe'

        $app = New-TestFolder 'App5' @('unins000.exe', 'app.exe')
        $r = New-TestRecord @{ UninstallString = "`"$(Join-Path $app 'unins000.exe')`" /SILENT" } | Resolve-InstallLocation
        $r.Path | Should -Be $app
        $r.Source | Should -Be 'UninstallCommand'
    }

    It 'nimmt den Deinstallationsbefehl nicht, wenn er msiexec oder einen fremden Starter aufruft' {
        $steam = New-TestFolder 'Steam' @('steam.exe')
        $r = New-TestRecord @{ UninstallString = "`"$(Join-Path $steam 'steam.exe')`" steam://uninstall/730" } | Resolve-InstallLocation
        $r.Path | Should -BeNullOrEmpty
        $r.Reason.Code | Should -Be 'LocationNoData'
        $r = New-TestRecord @{ UninstallString = 'MsiExec.exe /X{11111111-2222-3333-4444-555555555555}' } | Resolve-InstallLocation
        $r.Reason.Code | Should -Be 'LocationNoData'
    }

    It 'leitet bei MSI den gemeinsamen Ordner der Programm-Komponenten ab' {
        $dir = New-TestFolder 'Contoso\bin' @('app.exe', 'helper.exe')
        $script:components = @((Join-Path $dir 'app.exe'), (Join-Path $dir 'helper.exe'), 'C:\Windows\System32\contoso.dll', '02:\SOFTWARE\Contoso')
        Mock -ModuleName SoftwareInventory Get-MsiComponentPath { $script:components }
        $r = New-TestRecord @{ ProductCode = '{11111111-2222-3333-4444-555555555555}' } | Resolve-InstallLocation
        $r.Path | Should -Be $dir
        $r.Source | Should -Be 'MsiComponents'
        $r.Certain | Should -BeFalse
    }

    It 'nimmt bei portablen Programmen den Ordner der Datei' {
        $dir = New-TestFolder 'Portable' @('tool.exe')
        $r = New-TestRecord @{ FilePath = (Join-Path $dir 'tool.exe') } | Resolve-InstallLocation
        $r.Path | Should -Be $dir
        $r.Source | Should -Be 'FileSearch'
        $r.Certain | Should -BeTrue
    }

    It 'bietet Öffnen bei Store-Apps nicht an, den Pfad aber schon' {
        $dir = New-TestFolder 'Store'
        $r = New-TestRecord @{ InstallLocation = $dir; PackageFullName = 'Contoso.App_1.0_x64__abc' } | Resolve-InstallLocation
        $r.Path | Should -Be $dir
        $r.Source | Should -Be 'AppPackage'
        $r.CanOpen | Should -BeFalse
    }

    It 'nennt LocationNoData ohne jede Angabe und nimmt auch Ergebnisse von Get-SecurityRating' {
        $rating = [pscustomobject] @{ PSTypeName = 'SoftwareInventory.SecurityRating'; Name = 'Contoso Tool'; Record = (New-TestRecord) }
        ($rating | Resolve-InstallLocation).Reason.Code | Should -Be 'LocationNoData'
    }
}
