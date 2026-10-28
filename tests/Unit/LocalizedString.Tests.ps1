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
