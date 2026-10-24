BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

Describe 'Get-WingetSoftware' {
    BeforeAll {
        Mock -ModuleName SoftwareInventory Get-Command { $true } -ParameterFilter { $Name -eq 'Get-WinGetPackage' }
        Mock -ModuleName SoftwareInventory Get-WingetPackageData {
            [pscustomobject] @{ Name = '7-Zip'; Id = '7zip.7zip'; Source = 'winget'; InstalledVersion = '26.05'
                AvailableVersion = '26.06'; ProductCodes = @('7-Zip'); PackageFamilyNames = @() }
            [pscustomobject] @{ Name = 'GIMP'; Id = 'ARP\User\X64\GIMP-3_is1'; Source = ''; InstalledVersion = '3.2.4'
                AvailableVersion = $null; ProductCodes = @(); PackageFamilyNames = @() }
            [pscustomobject] @{ Name = 'WhatsApp'; Id = 'MSIX\5319275A.WhatsAppDesktop_2.2640.100.0_x64__cv1g1gvanyjgm'
                Source = ''; InstalledVersion = '2.2640.100.0'; AvailableVersion = $null; ProductCodes = @(); PackageFamilyNames = @() }
        }
        $result = InModuleScope SoftwareInventory { Get-WingetSoftware }
    }

    It 'übernimmt winget-ID und Update nur für Katalogpakete' {
        $zip = $result | Where-Object Name -eq '7-Zip'
        $zip.WingetId | Should -Be '7zip.7zip'
        $zip.AvailableVersion | Should -Be '26.06'
        $zip.MatchKeys | Should -Be @('arp:7-zip')
        ($result | Where-Object Name -eq 'GIMP').WingetId | Should -BeNullOrEmpty
    }

    It 'bildet Schlüssel aus ARP- und MSIX-IDs' {
        ($result | Where-Object Name -eq 'GIMP').MatchKeys | Should -Be @('arp:user:gimp-3_is1')
        ($result | Where-Object Name -eq 'WhatsApp').MatchKeys |
            Should -Be @('msix:5319275a.whatsappdesktop_2.2640.100.0_x64__cv1g1gvanyjgm')
    }

    It 'warnt und liefert nichts, wenn winget scheitert' {
        Mock -ModuleName SoftwareInventory Get-WingetPackageData { throw 'COM-Fehler' }
        $r = InModuleScope SoftwareInventory { Get-WingetSoftware -WarningVariable w -WarningAction SilentlyContinue; $w }
        "$r" | Should -Match 'COM-Fehler'
    }
}

Describe 'Get-AppxSoftware' {
    It 'filtert Frameworks, Systempakete und nicht entfernbare Pakete' {
        Mock -ModuleName SoftwareInventory Get-AppxPackage {
            [pscustomobject] @{ Name = 'Mozilla.Firefox'; Publisher = 'CN=Mozilla Corporation, O=Mozilla Corporation, C=US'
                Version = '158.0.1.0'; Architecture = 'X64'; PackageFullName = 'Mozilla.Firefox_158.0.1.0_x64__n80bbvh6b1yt2'
                PackageFamilyName = 'Mozilla.Firefox_n80bbvh6b1yt2'; InstallLocation = 'C:\Program Files\WindowsApps\x'
                IsFramework = $false; NonRemovable = $false; SignatureKind = 'Store' }
            [pscustomobject] @{ Name = 'Microsoft.VCLibs'; IsFramework = $true; NonRemovable = $false; SignatureKind = 'Store' }
            [pscustomobject] @{ Name = 'Microsoft.BioEnrollment'; IsFramework = $false; NonRemovable = $true; SignatureKind = 'System' }
        }
        $result = @(InModuleScope SoftwareInventory { Get-AppxSoftware })

        $result.Count | Should -Be 1
        $result[0].Publisher | Should -Be 'Mozilla Corporation'
        $result[0].InstallType | Should -Be 'MSIX'
        $result[0].MatchKeys | Should -Contain 'pfn:mozilla.firefox_n80bbvh6b1yt2'
    }
}

Describe 'Merge-SoftwareRecord' {
    BeforeAll {
        $merge = {
            param($Base, $Winget)
            InModuleScope SoftwareInventory -Parameters @{ B = $Base; W = $Winget } {
                $mk = { param($n, $s, $keys, $p) New-SoftwareRecord -Name $n -Source $s -Property $p | ForEach-Object { Add-MatchKey -Record $_ -Key $keys } }
                $base = foreach ($b in $B) { & $mk @b }
                $wg = foreach ($w in $W) { & $mk @w }
                Merge-SoftwareRecord -BaseRecord $base -WingetRecord $wg
            }
        }
    }

    It 'ordnet über den Registry-Schlüssel zu und ergänzt winget-Daten' {
        $r = & $merge @(
            @{ n = '7-Zip 26.05 (x64)'; s = 'Registry'; keys = @('arp:7-zip', 'arp:machine:7-zip'); p = @{ Version = '26.05'; InstallType = 'EXE' } }
        ) @(
            @{ n = '7-Zip'; s = 'Winget'; keys = @('arp:7-zip'); p = @{ Version = '26.05'; WingetId = '7zip.7zip'; AvailableVersion = '26.06' } }
        )
        @($r).Count | Should -Be 1
        $r.Name | Should -Be '7-Zip 26.05 (x64)'
        $r.WingetId | Should -Be '7zip.7zip'
        $r.AvailableVersion | Should -Be '26.06'
        $r.Sources | Should -Be @('Registry', 'Winget')
        $r.PSObject.Properties.Name | Should -Not -Contain 'MatchKeys'
    }

    It 'übernimmt bei Store-Apps den Anzeigenamen aus winget' {
        $r = & $merge @(
            @{ n = 'Mozilla.Firefox'; s = 'Appx'; keys = @('msix:ff_full', 'pfn:ff'); p = @{ InstallType = 'MSIX'; Version = '158.0' } }
        ) @(
            @{ n = 'Mozilla Firefox'; s = 'Winget'; keys = @('msix:ff_full'); p = @{ Version = '158.0' } }
        )
        $r.Name | Should -Be 'Mozilla Firefox'
    }

    It 'verwirft winget-Einträge, die eine Grundquelle ausgefiltert hat' {
        $r = & $merge @() @(
            @{ n = 'VCLibs'; s = 'Winget'; keys = @('pfn:vclibs'); p = @{ WingetId = 'Microsoft.VCLibs.14' } }
            @{ n = 'Hidden'; s = 'Winget'; keys = @('arp:machine:hidden'); p = @{} }
        )
        $r | Should -BeNullOrEmpty
    }

    It 'gleicht ohne Schlüssel über Name und Version ab, sonst eigener Datensatz' {
        $r = & $merge @(
            @{ n = 'Contoso Tool 2.1'; s = 'Registry'; keys = @('arp:contoso'); p = @{ Version = '2.1' } }
        ) @(
            @{ n = 'Contoso Tool'; s = 'Winget'; keys = @(); p = @{ Version = '2.1'; WingetId = 'Contoso.Tool' } }
            @{ n = 'Fabrikam'; s = 'Winget'; keys = @(); p = @{ Version = '1.0'; WingetId = 'Fabrikam.App' } }
        )
        ($r | Where-Object Name -eq 'Contoso Tool 2.1').WingetId | Should -Be 'Contoso.Tool'
        ($r | Where-Object Name -eq 'Fabrikam').InstallType | Should -Be 'Winget'
    }

    It 'ordnet zwei gleiche winget-IDs verschiedenen Installationen zu' {
        $r = & $merge @(
            @{ n = 'Tool (x64)'; s = 'Registry'; keys = @('arp:tool'); p = @{ Version = '2.0' } }
            @{ n = 'Tool (x86)'; s = 'Registry'; keys = @('arp:tool'); p = @{ Version = '1.0' } }
        ) @(
            @{ n = 'Tool'; s = 'Winget'; keys = @('arp:tool'); p = @{ Version = '1.0'; WingetId = 'T.Tool' } }
            @{ n = 'Tool'; s = 'Winget'; keys = @('arp:tool'); p = @{ Version = '2.0'; WingetId = 'T.Tool' } }
        )
        $r | ForEach-Object { $_.WingetId | Should -Be 'T.Tool' }
    }
}
