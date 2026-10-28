BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
    $script:ModuleRoot = Resolve-Path "$PSScriptRoot/../../src/SoftwareInventory"
}

Describe 'Texte des Moduls' {
    It 'lädt die Basistexte und setzt Platzhalter ein' {
        InModuleScope SoftwareInventory { Get-LocalizedString 'AdvisorErrorUnknownId' @('p-123') } | Should -Match "p-123"
        InModuleScope SoftwareInventory { Get-LocalizedString 'GibtEsNicht' } | Should -Be 'GibtEsNicht'
    }

    It 'enthält jeden im Code fest genannten Schlüssel' {
        $used = Get-ChildItem $ModuleRoot -Recurse -Filter '*.ps1' | Select-String -Pattern "Get-LocalizedString\s+(?:-Name\s+)?'(?<key>\w+)'" -AllMatches |
            ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups['key'].Value } | Sort-Object -Unique
        $used | Should -Not -BeNullOrEmpty
        $strings = InModuleScope SoftwareInventory { $script:Strings }
        foreach ($key in $used) { $strings.ContainsKey($key) | Should -BeTrue -Because "Schlüssel '$key' wird im Code verwendet" }
    }

    It 'enthält zu jedem Code einer Meldung einen Text' {
        $used = Get-ChildItem $ModuleRoot -Recurse -Filter '*.ps1' | Select-String -Pattern 'New-InventoryMessage\s+(?<key>\w+)' -AllMatches |
            ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups['key'].Value } | Sort-Object -Unique
        # Codes, die über eine Variable gewählt werden ($code)
        $used = @($used) + 'PossiblyAffected', 'PossiblyAffectedKev', 'UpdateAvailable', 'UpdateAvailableUnconfirmed', 'ActionVerbUpdate', 'ActionVerbUninstall'
        # Codes des erhöhten Helfers (Text bildet das Modul) und aller bekannten Exit-Codes
        $used += Select-String -Path (Join-Path $ModuleRoot 'Elevated\ElevatedHelper.ps1') -Pattern "Code = '(?<key>\w+)'" -AllMatches |
            ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups['key'].Value }
        $used += InModuleScope SoftwareInventory { $script:ExitCodeMap.Keys | ForEach-Object { "ExitCode$_" } }
        $strings = InModuleScope SoftwareInventory { $script:Strings }
        foreach ($code in $used) { $strings.ContainsKey("Reason$code") | Should -BeTrue -Because "Code '$code' wird im Code verwendet" }
    }

    It 'liefert Meldungen mit Code, Args und Text, auch verschachtelt' {
        $m = InModuleScope SoftwareInventory {
            $inner = New-InventoryMessage ServiceDisabled 'NVD'
            New-InventoryMessage NotCheckedBecause (, $inner)
        }
        $m.Code | Should -Be 'NotCheckedBecause'
        $m.Args[0].Code | Should -Be 'ServiceDisabled'
        $m.Text | Should -Be 'Nicht auf Lücken geprüft: Dienst NVD nicht aktiviert'

        $list = InModuleScope SoftwareInventory {
            New-InventoryMessage NoLatestVersion (, @((New-InventoryMessage ServiceDisabled 'GitHub'), (New-InventoryMessage WingetSearchNoPublisher)))
        }
        $list.Text | Should -Be 'Dienst GitHub nicht aktiviert; winget-Suche braucht einen Hersteller'

        $data = InModuleScope SoftwareInventory -Parameters @{ M = $m } { ConvertTo-MessageData $M }
        $data.code | Should -Be 'NotCheckedBecause'
        $data.args[0].code | Should -Be 'ServiceDisabled'
        $data.args[0].args | Should -Be @('NVD')
    }

    It 'enthält die Texte der Nutzungsbedingungen zu jedem Dienst' {
        $missing = InModuleScope SoftwareInventory {
            $keys = @('ServiceTermsGeneralPrivate', 'ServiceTermsGeneralCompany')
            foreach ($e in $script:ServiceTerms) {
                $keys += "ServiceTerms$($e.Service)Name", "ServiceTerms$($e.Service)Terms"
                if ($e.CompanyHint) { $keys += "ServiceTerms$($e.Service)Company" }
            }
            $keys | Where-Object { -not $script:Strings.ContainsKey($_) }
        }
        $missing | Should -BeNullOrEmpty
    }

    It 'enthält alle Texte des HTML-Berichts' {
        $used = Select-String -Path (Join-Path $ModuleRoot 'Private\ReportHtml.ps1') -Pattern '& \$t (?<key>\w+)' -AllMatches |
            ForEach-Object { $_.Matches } | ForEach-Object { "Report$($_.Groups['key'].Value)" }
        $used += 'Red', 'Yellow', 'Green', 'Gray' | ForEach-Object { "ReportRating$_" }
        $used += 'Affected', 'PossiblyAffected', 'Informational' | ForEach-Object { "ReportAssessment$_" }
        $strings = InModuleScope SoftwareInventory { $script:Strings }
        foreach ($key in $used | Sort-Object -Unique) { $strings.ContainsKey($key) | Should -BeTrue -Because "Bericht nutzt '$key'" }
    }

    It 'enthält die Fortschrittstexte mit und ohne Zähler' {
        $used = Get-ChildItem $ModuleRoot -Recurse -Filter '*.ps1' | Select-String -Pattern 'Write-CheckProgress\b.*?-Activity\s+(?<key>\w+)' -AllMatches |
            ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups['key'].Value } | Sort-Object -Unique
        $used | Should -Not -BeNullOrEmpty
        $strings = InModuleScope SoftwareInventory { $script:Strings }
        foreach ($key in $used) { $strings.ContainsKey($key) | Should -BeTrue -Because "Fortschritt '$key' wird im Code verwendet" }
        foreach ($key in 'ProgressCheckUpdates', 'ProgressCheckVulnerabilities') { $strings.ContainsKey("${key}Counted") | Should -BeTrue }
    }

    It 'enthält die zusammengesetzten Schlüssel der Berater-Tools, Fehlercodes und Vorgaben' {
        $missing = InModuleScope SoftwareInventory {
            $keys = [System.Collections.Generic.List[string]]::new()
            foreach ($tool in $script:AdvisorTools.Values) {
                $keys.Add($tool.Text)
                foreach ($p in $tool.Properties.Values) { $keys.Add($p.Text) }
            }
            foreach ($code in 'UnknownTool', 'InvalidArguments', 'InvalidId', 'UnknownId', 'InvalidLimit', 'InvalidRating', 'ReasonMissing', 'NoUpdateKnown', 'ToolFailed') { $keys.Add("AdvisorError$code") }
            foreach ($name in $script:AdvisorPresets.Keys) { if (-not $script:AdvisorPresets[$name].Label) { $keys.Add("AdvisorPresetLabel$name") } }
            $keys | Where-Object { -not $script:Strings.ContainsKey($_) }
        }
        $missing | Should -BeNullOrEmpty
    }
}
