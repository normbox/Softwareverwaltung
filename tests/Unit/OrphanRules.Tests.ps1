BeforeDiscovery {
    $table = Get-Content -Raw "$PSScriptRoot/../Data/registry-orphan-cases.json" | ConvertFrom-Json
    $OrphanCases = @($table.cases | ForEach-Object { @{ Name = $_.name; Case = $_ } })
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\SoftwareInventory\SoftwareInventory.psd1') -Force
}

Describe 'Test-OrphanedRegistryEntry: gemeinsame Fälletabelle mit dem Helfer (OrphanRules.cs)' {
    BeforeAll {
        $script:Pf = [Environment]::GetFolderPath('ProgramFiles')
        $script:Pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
        $script:Sys = [Environment]::GetFolderPath('System')
        $script:Win = $env:WINDIR
        $script:Root = [System.IO.Path]::GetPathRoot($script:Pf)

        function Expand-OrphanText($Text) {
            if ($null -eq $Text) { return $null }
            $t = ([string] $Text).Replace('{PF86}', $script:Pf86).Replace('{PF}', $script:Pf).Replace('{SYS}', $script:Sys).Replace('{WIN}', $script:Win).Replace('{ROOT}', $script:Root)
            # {U+XXXX} wird zum Zeichen mit diesem Codepunkt (kein Escape-Text für Sonderzeichen in der Tabelle).
            [regex]::Replace($t, '\{U\+([0-9A-Fa-f]{4})\}', { param($m) [string] [char] [Convert]::ToInt32($m.Groups[1].Value, 16) })
        }

        # Das Dateisystem wird aus der Tabelle nachgebildet: vorhandene Dateien/Ordner, bekannte Laufwerke mit ihrer Art.
        Mock -ModuleName SoftwareInventory Test-Path {
            $p = [string] $LiteralPath
            if ($PathType -eq 'Leaf') { return [bool] ($script:OrphanFiles -contains $p) }
            [bool] (($script:OrphanFiles -contains $p) -or ($script:OrphanDirs -contains $p))
        }
        Mock -ModuleName SoftwareInventory Get-PathExistence {
            $p = [string] $Path
            if ($script:OrphanDenied -contains $p) { return 'Unknown' }
            if (($script:OrphanFiles -contains $p) -or ($script:OrphanDirs -contains $p)) { 'Exists' } else { 'Missing' }
        }
        Mock -ModuleName SoftwareInventory Test-PathRootReachable {
            $root = [System.IO.Path]::GetPathRoot([string] $Path)
            [bool] ($root -and $script:OrphanDrives.ContainsKey($root))
        }
        Mock -ModuleName SoftwareInventory Get-PathDriveType {
            if ($script:OrphanDrives.ContainsKey([string] $Root)) { $script:OrphanDrives[[string] $Root] } else { $null }
        }
    }

    It 'liefert für "<Name>" das Ergebnis der Tabelle' -ForEach $OrphanCases {
        $script:OrphanFiles = @($Case.files | Where-Object { $_ } | ForEach-Object { Expand-OrphanText $_ })
        $script:OrphanDirs = @($Case.dirs | Where-Object { $_ } | ForEach-Object { Expand-OrphanText $_ })
        $script:OrphanDenied = @($Case.denied | Where-Object { $_ } | ForEach-Object { Expand-OrphanText $_ })
        $script:OrphanDrives = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($Case.PSObject.Properties['drives']) {
            foreach ($property in $Case.drives.PSObject.Properties) { $script:OrphanDrives[(Expand-OrphanText $property.Name)] = $property.Value }
        }
        else { $script:OrphanDrives[$script:Root] = 'Fixed' }

        $inputs = @{
            Msi       = [bool] ($Case.PSObject.Properties['msi'] -and $Case.msi)
            Uninstall = Expand-OrphanText $(if ($Case.PSObject.Properties['uninstall']) { $Case.uninstall })
            Quiet     = Expand-OrphanText $(if ($Case.PSObject.Properties['quiet']) { $Case.quiet })
            Location  = Expand-OrphanText $(if ($Case.PSObject.Properties['location']) { $Case.location })
            Icon      = Expand-OrphanText $(if ($Case.PSObject.Properties['icon']) { $Case.icon })
            Arch      = if ($Case.PSObject.Properties['architecture']) { [string] $Case.architecture } else { '' }
        }
        $actual = InModuleScope SoftwareInventory -Parameters @{ I = $inputs } {
            # Wie ConvertFrom-UninstallKey die rohen Registry-Werte aufbereitet, dann die eigentliche Prüfung.
            $record = [pscustomobject] @{
                UninstallString      = ConvertTo-NullIfEmpty $I.Uninstall
                QuietUninstallString = ConvertTo-NullIfEmpty $I.Quiet
                InstallLocation      = ConvertTo-NullIfEmpty $I.Location
                DisplayIcon          = ConvertFrom-DisplayIcon $I.Icon
                Architecture         = $I.Arch
            }
            Test-OrphanedRegistryEntry -Record $record -IsMsi $I.Msi
        }
        $actual | Should -Be ([bool] $Case.orphaned)
    }

}

Describe 'Get-PathExistence und Umfang der Fälletabelle (ohne Mocks, echtes Dateisystem)' {
    It 'Get-PathExistence: nur "nicht gefunden" ist Missing, Zugriff verweigert ist Unknown' {
        $folder = Join-Path ([System.IO.Path]::GetTempPath()) ('orph-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $folder
        try {
            $file = Join-Path $folder 'a.txt'
            Set-Content -LiteralPath $file -Value 'x'
            # Windows fällt bei verweigertem Attributzugriff auf das Auflisten des Ordners zurück: für ein echtes
            # „Zugriff verweigert“ braucht es beides (Attribute der Datei und Auflisten des Ordners).
            $lockedDir = Join-Path $folder 'locked'
            $null = New-Item -ItemType Directory -Path $lockedDir
            $denied = Join-Path $lockedDir 'denied.txt'
            Set-Content -LiteralPath $denied -Value 'x'
            $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            foreach ($item in @(@($denied, 'ReadAttributes'), @($lockedDir, 'ListDirectory'))) {
                $acl = Get-Acl -LiteralPath $item[0]
                $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($me, $item[1], 'Deny'))
                Set-Acl -LiteralPath $item[0] -AclObject $acl
            }
            $result = InModuleScope SoftwareInventory -Parameters @{ F = $folder } {
                @{
                    File    = Get-PathExistence -Path (Join-Path $F 'a.txt')
                    Dir     = Get-PathExistence -Path $F
                    Missing = Get-PathExistence -Path (Join-Path $F 'gibt-es-nicht.txt')
                    NoDir   = Get-PathExistence -Path (Join-Path $F 'kein\ordner\x.txt')
                    Denied  = Get-PathExistence -Path (Join-Path $F 'locked\denied.txt')
                    BadName = Get-PathExistence -Path ($F + '\' + [char]0x3C + 'x')
                }
            }
            $result.File | Should -Be 'Exists'
            $result.Dir | Should -Be 'Exists'
            $result.Missing | Should -Be 'Missing'
            $result.NoDir | Should -Be 'Missing'
            $result.Denied | Should -Be 'Unknown'
            $result.BadName | Should -Be 'Unknown'
        }
        finally {
            # Erst das Auflisten des Ordners wieder freigeben, sonst lässt sich die Datei darin nicht mehr ansprechen.
            foreach ($item in @((Join-Path $folder 'locked'), (Join-Path $folder 'locked\denied.txt'))) {
                if (Test-Path -LiteralPath $item) {
                    $acl = Get-Acl -LiteralPath $item
                    $acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' } | ForEach-Object { $null = $acl.RemoveAccessRule($_) }
                    Set-Acl -LiteralPath $item -AclObject $acl
                }
            }
            Remove-Item -LiteralPath $folder -Recurse -Force
        }
    }

    It 'enthält genug Fälle' {
        $table = Get-Content -Raw "$PSScriptRoot/../Data/registry-orphan-cases.json" | ConvertFrom-Json
        $table.cases.Count | Should -BeGreaterThan 35
        @($table.cases | Where-Object { $_.orphaned }).Count | Should -BeGreaterThan 8
        @($table.cases | Where-Object { -not $_.orphaned }).Count | Should -BeGreaterThan 20
    }
}
