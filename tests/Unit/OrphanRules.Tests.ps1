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
        $script:Sys = [Environment]::GetFolderPath('System')
        $script:Win = $env:WINDIR
        $script:Root = [System.IO.Path]::GetPathRoot($script:Pf)

        function Expand-OrphanText($Text) {
            if ($null -eq $Text) { return $null }
            $t = ([string] $Text).Replace('{PF}', $script:Pf).Replace('{SYS}', $script:Sys).Replace('{WIN}', $script:Win).Replace('{ROOT}', $script:Root)
            # {U+XXXX} wird zum Zeichen mit diesem Codepunkt (kein Escape-Text für Sonderzeichen in der Tabelle).
            [regex]::Replace($t, '\{U\+([0-9A-Fa-f]{4})\}', { param($m) [string] [char] [Convert]::ToInt32($m.Groups[1].Value, 16) })
        }

        # Das Dateisystem wird aus der Tabelle nachgebildet: vorhandene Dateien/Ordner, bekannte Laufwerke mit ihrer Art.
        Mock -ModuleName SoftwareInventory Test-Path {
            $p = [string] $LiteralPath
            if ($PathType -eq 'Leaf') { return [bool] ($script:OrphanFiles -contains $p) }
            [bool] (($script:OrphanFiles -contains $p) -or ($script:OrphanDirs -contains $p))
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
        }
        $actual = InModuleScope SoftwareInventory -Parameters @{ I = $inputs } {
            # Wie ConvertFrom-UninstallKey die rohen Registry-Werte aufbereitet, dann die eigentliche Prüfung.
            $record = [pscustomobject] @{
                UninstallString      = ConvertTo-NullIfEmpty $I.Uninstall
                QuietUninstallString = ConvertTo-NullIfEmpty $I.Quiet
                InstallLocation      = ConvertTo-NullIfEmpty $I.Location
                DisplayIcon          = ConvertFrom-DisplayIcon $I.Icon
            }
            Test-OrphanedRegistryEntry -Record $record -IsMsi $I.Msi
        }
        $actual | Should -Be ([bool] $Case.orphaned)
    }

    It 'enthält genug Fälle' {
        $table = Get-Content -Raw "$PSScriptRoot/../Data/registry-orphan-cases.json" | ConvertFrom-Json
        $table.cases.Count | Should -BeGreaterThan 35
        @($table.cases | Where-Object { $_.orphaned }).Count | Should -BeGreaterThan 8
        @($table.cases | Where-Object { -not $_.orphaned }).Count | Should -BeGreaterThan 20
    }
}
