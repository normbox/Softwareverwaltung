BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-Manifest {
        param([string] $Name, [string] $DisplayName, [string] $Publisher, [bool] $Sparse)
        $dir = New-Item -ItemType Directory (Join-Path $TestDrive $Name) -Force
        $external = if ($Sparse) { '<uap10:AllowExternalContent>true</uap10:AllowExternalContent>' } else { '' }
        @"
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10" xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10">
  <Properties><DisplayName>$DisplayName</DisplayName><PublisherDisplayName>$Publisher</PublisherDisplayName>$external</Properties>
</Package>
"@ | Set-Content (Join-Path $dir 'AppxManifest.xml')
        $dir.FullName
    }

    # Baut Basis-Datensätze wie Get-RegistrySoftware/Get-AppxSoftware und führt sie zusammen.
    function Invoke-Merge {
        param([hashtable[]] $Registry, [hashtable[]] $Sparse)
        InModuleScope SoftwareInventory -Parameters @{ R = $Registry; S = $Sparse } {
            $base = @(
                foreach ($r in $R) {
                    New-SoftwareRecord -Name $r.Name -Source Registry -Property @{ Publisher = $r.Publisher; InstallType = 'EXE' } |
                        ForEach-Object { Add-MatchKey -Record $_ -Key @("arp:$($r.Name)") }
                }
                foreach ($s in $S) {
                    $rec = New-SoftwareRecord -Name $s.Name -Source Appx -Property @{
                        Publisher = $s.Publisher; InstallType = 'MSIX'; PackageFullName = "$($s.Name)_1.0_neutral__x"; Flags = [string[]] @('SparsePackage')
                    }
                    $rec | Add-Member -NotePropertyName CompanionInfo -NotePropertyValue @{ DisplayName = $s.DisplayName; PublisherDisplayName = $s.Publisher }
                    Add-MatchKey -Record $rec -Key @("msix:$($s.Name)")
                }
            )
            Merge-SoftwareRecord -BaseRecord $base -WingetRecord @()
        }
    }
}

Describe 'Get-AppxSoftware: Sparse Packages' {
    It 'markiert Pakete mit AllowExternalContent und liest Anzeigenamen aus dem Manifest' {
        $sparse = New-Manifest -Name 'sparse' -DisplayName 'WinMerge' -Publisher 'WinMerge' -Sparse $true
        $normal = New-Manifest -Name 'normal' -DisplayName 'Calculator' -Publisher 'Microsoft' -Sparse $false
        Mock -ModuleName SoftwareInventory Get-AppxPackage {
            foreach ($case in @(@{ Name = 'WinMerge'; Location = $sparse }, @{ Name = 'Microsoft.WindowsCalculator'; Location = $normal })) {
                [pscustomobject] @{ Name = $case.Name; Publisher = 'CN=Contoso'; Version = '1.0.8.0'; Architecture = 'Neutral'
                    PackageFullName = "$($case.Name)_1.0.8.0_neutral__x"; PackageFamilyName = "$($case.Name)_x"
                    InstallLocation = $case.Location; IsFramework = $false; NonRemovable = $false; SignatureKind = 'Developer' }
            }
        }
        $result = InModuleScope SoftwareInventory { Get-AppxSoftware }

        $winMerge = $result | Where-Object Name -eq 'WinMerge'
        $winMerge.Flags | Should -Be @('SparsePackage')
        $winMerge.CompanionInfo.DisplayName | Should -Be 'WinMerge'
        ($result | Where-Object Name -eq 'Microsoft.WindowsCalculator').Flags | Should -BeNullOrEmpty
    }
}

Describe 'Merge-SoftwareRecord: Begleitpakete' {
    It 'hängt ein Sparse Package über den Namen an das Programm' {
        $r = @(Invoke-Merge -Registry @(@{ Name = 'WinMerge 2.16.58.2 x64'; Publisher = 'Thingamahoochie Software' }) `
                -Sparse @(@{ Name = 'WinMerge'; DisplayName = 'WinMerge'; Publisher = 'WinMerge' }))

        $r.Count | Should -Be 1
        $r[0].Name | Should -Be 'WinMerge 2.16.58.2 x64'
        $r[0].Companions | Should -Be @('WinMerge_1.0_neutral__x')
        $r[0].PSObject.Properties.Name | Should -Not -Contain 'CompanionInfo'
    }

    It 'hängt es über den Hersteller an, wenn es genau ein Programm dieses Herstellers gibt' {
        $r = @(Invoke-Merge -Registry @(@{ Name = 'Contoso Studio'; Publisher = 'Contoso Ltd.' }, @{ Name = 'Fabrikam'; Publisher = 'Fabrikam' }) `
                -Sparse @(@{ Name = 'CSContextMenu'; DisplayName = 'CS Shell Extension'; Publisher = 'Contoso' }))

        $r.Count | Should -Be 2
        ($r | Where-Object Name -eq 'Contoso Studio').Companions | Should -Be @('CSContextMenu_1.0_neutral__x')
    }

    It 'lässt das Paket stehen, wenn die Zuordnung nicht eindeutig ist' {
        $r = @(Invoke-Merge -Registry @(
                @{ Name = 'Bitdefender Agent'; Publisher = 'Bitdefender' }
                @{ Name = 'Bitdefender Total Security'; Publisher = 'Bitdefender' }
            ) -Sparse @(@{ Name = 'BDContextualMenu'; DisplayName = 'Bitdefender CL Contextual Menu'; Publisher = 'Bitdefender SRL' }))

        $r.Count | Should -Be 3
        $menu = $r | Where-Object Name -eq 'BDContextualMenu'
        $menu.Flags | Should -Be @('SparsePackage')
        $r | Where-Object Companions | Should -BeNullOrEmpty
    }

    It 'bevorzugt den genau gleichen Namen vor mehreren Präfix-Treffern' {
        $r = @(Invoke-Merge -Registry @(
                @{ Name = 'Microsoft Edge'; Publisher = 'Microsoft Corporation' }
                @{ Name = 'Microsoft Edge Update'; Publisher = $null }
                @{ Name = 'Microsoft Edge WebView2 Runtime'; Publisher = $null }
            ) -Sparse @(@{ Name = 'Microsoft.MicrosoftEdge.Stable'; DisplayName = 'Microsoft Edge'; Publisher = 'Microsoft Corporation' }))

        $r.Count | Should -Be 3
        ($r | Where-Object Name -eq 'Microsoft Edge').Companions | Should -Be @('Microsoft.MicrosoftEdge.Stable_1.0_neutral__x')
    }

    It 'findet den Namen auch als ganze Wörter im Programmnamen' {
        $r = @(Invoke-Merge -Registry @(@{ Name = 'Microsoft OneDrive'; Publisher = 'Microsoft Corporation' }, @{ Name = 'Microsoft 365'; Publisher = 'Microsoft Corporation' }) `
                -Sparse @(@{ Name = 'Microsoft.OneDriveSync'; DisplayName = 'OneDrive'; Publisher = 'Microsoft Corporation' }))

        $r.Count | Should -Be 2
        ($r | Where-Object Name -eq 'Microsoft OneDrive').Companions | Should -Be @('Microsoft.OneDriveSync_1.0_neutral__x')
    }

    It 'ordnet nicht über ein Namenspräfix mitten im Wort zu' {
        $r = @(Invoke-Merge -Registry @(@{ Name = 'WinMergeTools'; Publisher = 'Other' }) `
                -Sparse @(@{ Name = 'WinMerge'; DisplayName = 'WinMerge'; Publisher = 'WinMerge' }))

        $r.Count | Should -Be 2
    }
}

Describe 'ConvertTo-PublisherKey' {
    It 'entfernt Rechtsform und Satzzeichen' {
        InModuleScope SoftwareInventory {
            ConvertTo-PublisherKey 'Bitdefender SRL' | Should -Be 'bitdefender'
            ConvertTo-PublisherKey 'Contoso, Inc.' | Should -Be 'contoso'
            ConvertTo-PublisherKey 'Anthropic, PBC' | Should -Be 'anthropic'
            ConvertTo-PublisherKey '' | Should -BeNullOrEmpty
        }
    }
}
