BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
    $script:ModuleRoot = Resolve-Path "$PSScriptRoot/../../src/SoftwareInventory"
}

Describe 'Texte des Moduls' {
    It 'lädt die Basistexte und setzt Platzhalter ein' {
        InModuleScope SoftwareInventory { Get-LocalizedString 'AdvisorErrorUnknownId' @('p-123') } | Should -Match "p-123"
        InModuleScope SoftwareInventory { Get-LocalizedString 'GibtEsNicht' } | Should -Be 'GibtEsNicht'
    }

    It 'wirft nie, wenn Argumente nicht zu den Platzhaltern passen, und vermerkt das im Fehlerprotokoll' {
        $appData = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Mock -ModuleName SoftwareInventory Get-AppDataDirectory { $appData }
        $text = InModuleScope SoftwareInventory { Get-LocalizedString 'ReasonNewerInstallNextTo' @('Nur eins') }
        $text | Should -Be 'Neuere Installation daneben: {0} {1}'
        $message = InModuleScope SoftwareInventory { New-InventoryMessage NewerInstallNextTo 'Nur eins' }
        $message.Code | Should -Be 'NewerInstallNextTo'
        $message.Text | Should -Be 'Neuere Installation daneben: {0} {1}'
        $errorLog = Get-ChildItem (Join-Path $appData 'logs') -Filter 'app-errors-*.log' | Get-Content -Raw
        $errorLog | Should -Match 'ReasonNewerInstallNextTo'
        $errorLog | Should -Not -Match 'Nur eins' -Because 'nur Schlüssel und Anzahl, keine Inhalte'
        InModuleScope SoftwareInventory {
            Test-InventoryMessageArgs -Code NewerInstallNextTo -Arguments @('Jan', '0.8.8') | Should -BeTrue
            Test-InventoryMessageArgs -Code NewerInstallNextTo -Arguments @('Jan') | Should -BeFalse
            Test-InventoryMessageArgs -Code NewerInstallNextTo | Should -BeFalse
            Test-InventoryMessageArgs -Code OrphanedEntry | Should -BeTrue
            Test-InventoryMessageArgs -Code GibtEsNicht -Arguments @('x') | Should -BeTrue
        }
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
        $helperSources = Get-ChildItem (Join-Path $ModuleRoot '..\SoftwareInventory.Helper') -Filter '*.cs'
        $helperCodes = @($helperSources | Select-String -Pattern 'new Problem\("(?<key>\w+)"|new RestorePointOutcome\("\w+", "(?<key>\w+)"|SetError\(\w+, "(?<key>\w+)"' -AllMatches |
            ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups['key'].Value } | Sort-Object -Unique)
        $helperCodes | Should -Contain 'HelperCommandMismatch'
        $helperCodes | Should -Contain 'RestorePointNotCreated'
        $used += $helperCodes
        $used += InModuleScope SoftwareInventory { $script:ExitCodeMap.Keys | ForEach-Object { "ExitCode$_" } }
        $strings = InModuleScope SoftwareInventory { $script:Strings }
        foreach ($code in $used) { $strings.ContainsKey("Reason$code") | Should -BeTrue -Because "Code '$code' wird im Code verwendet" }
    }

    It 'hat zu jedem Prüfcode der .reg-Sicherung einen Text (Backup<Code>), auch wenn der Helfer ihn nur mit Präfix meldet' {
        # Der Helfer gibt die Codes von RegistryBackupRules als einfache Zeichenfolgen zurück und meldet sie dem Modul
        # mit dem Präfix "Backup" (z. B. BackupBadHeader). Der Test oben sieht nur new Problem("…"); dieser prüft die
        # Codes der gemeinsamen Fälletabelle und die Dateiprobleme gegen die psd1.
        $table = Get-Content -Raw "$PSScriptRoot/../Data/registry-backup-cases.json" | ConvertFrom-Json
        $codes = @($table.cases | Where-Object { $_.expected } | ForEach-Object { $_.expected } | Sort-Object -Unique)
        $codes.Count | Should -BeGreaterThan 8
        $strings = InModuleScope SoftwareInventory { $script:Strings }
        foreach ($code in @($codes) + @('Missing', 'TooLarge', 'BadEncoding', 'MetadataMissing', 'MetadataInvalid', 'NotFound')) {
            $strings.ContainsKey("ReasonBackup$code") | Should -BeTrue -Because "Code 'Backup$code' wird gemeldet, es fehlt der Text ReasonBackup$code"
        }
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
