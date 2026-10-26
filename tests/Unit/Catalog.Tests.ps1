BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-TestRecord {
        param([string] $Name, [string] $Publisher, [string] $WingetId, [string] $PackageFamilyName, [string] $Version = '1.0')
        InModuleScope SoftwareInventory -Parameters @{ N = $Name; P = $Publisher; W = $WingetId; F = $PackageFamilyName; V = $Version } {
            New-SoftwareRecord -Name $N -Source Registry -Property @{ Publisher = $P; WingetId = $W; PackageFamilyName = $F; Version = $V }
        }
    }
}

Describe 'Katalogdateien im Repository' {
    BeforeDiscovery {
        $files = Get-ChildItem "$PSScriptRoot/../../src/SoftwareInventory/Catalog" -Filter '*.json' | ForEach-Object { @{ File = $_.FullName; Name = $_.Name } }
    }

    It '<Name> ist gültig' -TestCases $files {
        $entry = Get-Content $File -Raw | ConvertFrom-Json
        $problems = InModuleScope SoftwareInventory -Parameters @{ E = $entry; F = [IO.Path]::GetFileNameWithoutExtension($File) } { Test-CatalogEntry -Entry $E -FileName $F }
        $problems | Should -BeNullOrEmpty
    }

    It 'hat keine doppelten Ids und winget-IDs' {
        $catalog = InModuleScope SoftwareInventory { Get-SoftwareCatalog -Force }
        $catalog.Count | Should -BeGreaterThan 0
        ($catalog.Id | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
        ($catalog | ForEach-Object { $_.Match.PSObject.Properties['WingetId']?.Value } | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
    }
}

Describe 'Test-CatalogEntry' {
    It 'meldet <Case>' -TestCases @(
        @{ Case = 'fehlende Id'; Json = '{"Name":"X","Match":{"WingetId":["X.X"]}}'; Expected = '*Id fehlt*' }
        @{ Case = 'Id passt nicht zur Datei'; Json = '{"Id":"other","Name":"X","Match":{"WingetId":["X.X"]}}'; Expected = '*Dateinamen*' }
        @{ Case = 'Name-Muster ohne Hersteller'; Json = '{"Id":"x","Name":"X","Match":{"NamePattern":"^X"}}'; Expected = '*braucht Publisher*' }
        @{ Case = 'ungültiges Muster'; Json = '{"Id":"x","Name":"X","Match":{"NamePattern":"^X(","Publisher":["Contoso"]}}'; Expected = '*Ungültiges Muster*' }
        @{ Case = 'falsches Repository'; Json = '{"Id":"x","Name":"X","Match":{"WingetId":["X.X"]},"GitHub":{"Repository":"nur-ein-teil"}}'; Expected = '*owner/repo*' }
        @{ Case = 'TagPattern ohne Gruppe'; Json = '{"Id":"x","Name":"X","Match":{"WingetId":["X.X"]},"GitHub":{"Repository":"a/b","TagPattern":"^v(.+)$"}}'; Expected = '*(?<version>*' }
        @{ Case = 'zu kurzer Hersteller'; Json = '{"Id":"x","Name":"X","Match":{"NamePattern":"^X","Publisher":["ai"]}}'; Expected = '*Vergleichsschlüssel*' }
        @{ Case = 'CPE mit Version'; Json = '{"Id":"x","Name":"X","Match":{"WingetId":["X.X"]},"Cpe":["cpe:2.3:a:x:x:1.0"]}'; Expected = '*ohne Version*' }
        @{ Case = 'CPE ohne Präfix'; Json = '{"Id":"x","Name":"X","Match":{"WingetId":["X.X"]},"Cpe":["x:x"]}'; Expected = '*cpe:2.3*' }
        @{ Case = 'KEV ohne Hersteller'; Json = '{"Id":"x","Name":"X","Match":{"WingetId":["X.X"]},"Kev":[{"ProductPattern":"^X$"}]}'; Expected = '*Kev.Vendor fehlt*' }
        @{ Case = 'KEV mit ungültigem Muster'; Json = '{"Id":"x","Name":"X","Match":{"WingetId":["X.X"]},"Kev":[{"Vendor":"X","ProductPattern":"(x"}]}'; Expected = '*Ungültiges Muster*' }
        @{ Case = 'KevFixed ohne Kev'; Json = '{"Id":"x","Name":"X","Match":{"WingetId":["X.X"]},"KevFixed":{"CVE-2025-0001":"1.0"}}'; Expected = '*KevFixed braucht eine Kev-Zuordnung*' }
        @{ Case = 'KevFixed mit falscher ID'; Json = '{"Id":"x","Name":"X","Match":{"WingetId":["X.X"]},"Kev":[{"Vendor":"X","ProductPattern":"^X$"}],"KevFixed":{"2025-1":"1.0"}}'; Expected = '*keine CVE-ID*' }
        @{ Case = 'KevFixed mit unlesbarer Version'; Json = '{"Id":"x","Name":"X","Match":{"WingetId":["X.X"]},"Kev":[{"Vendor":"X","ProductPattern":"^X$"}],"KevFixed":{"CVE-2025-0001":"neu"}}'; Expected = '*nicht lesbar*' }
        @{ Case = 'Versionsmuster ohne Gruppe'; Json = '{"Id":"x","Name":"X","Match":{"WingetId":["X.X"]},"CpeVersionPattern":"^(.+)$"}'; Expected = '*CpeVersionPattern braucht*' }
    ) {
        $problems = InModuleScope SoftwareInventory -Parameters @{ E = ($Json | ConvertFrom-Json) } { Test-CatalogEntry -Entry $E -FileName 'x' }
        ($problems -join "`n") | Should -BeLike $Expected
    }

    It 'überspringt fehlerhafte Dateien mit Warnung' {
        $dir = Join-Path $TestDrive 'catalog'
        New-Item -ItemType Directory $dir | Out-Null
        '{"Id":"good","Name":"Good","Match":{"WingetId":["Good.Good"]}}' | Set-Content "$dir\good.json"
        '{ kaputt' | Set-Content "$dir\broken.json"
        $entries = @(InModuleScope SoftwareInventory -Parameters @{ D = $dir } { Get-SoftwareCatalog -Path $D -WarningAction SilentlyContinue })
        $entries.Id | Should -Be @('good')
    }
}

Describe 'Find-CatalogEntry' {
    BeforeAll {
        $catalog = InModuleScope SoftwareInventory { Get-SoftwareCatalog -Force }
    }

    It 'ordnet über <Case> zu' -TestCases @(
        @{ Case = 'winget-ID'; Record = @{ Name = 'Irgendwas'; Publisher = 'Fremd'; WingetId = 'Audacity.Audacity' }; Id = 'audacity'; By = 'WingetId' }
        @{ Case = 'PackageFamilyName'; Record = @{ Name = 'Telegram'; Publisher = 'X'; PackageFamilyName = 'TelegramMessengerLLP.TelegramDesktop_t4vj0pshhgkwm' }; Id = 'telegram-desktop'; By = 'PackageFamilyName' }
        @{ Case = 'Name und Hersteller'; Record = @{ Name = 'WinMerge x64'; Publisher = 'Thingamahoochie Software' }; Id = 'winmerge'; By = 'NameAndPublisher' }
        @{ Case = 'Name und Hersteller (portabel)'; Record = @{ Name = 'ComfyUI'; Publisher = 'Comfy Org' }; Id = 'comfyui-desktop'; By = 'NameAndPublisher' }
    ) {
        $r = New-TestRecord @Record
        $hit = InModuleScope SoftwareInventory -Parameters @{ R = $r; C = $catalog } { Find-CatalogEntry -Record $R -Catalog $C }
        $hit.Entry.Id | Should -Be $Id
        $hit.MatchedBy | Should -Be $By
    }

    It 'ordnet nie über den Namen allein zu: <Case>' -TestCases @(
        @{ Case = 'WinMerge-Erweiterung eines anderen Herausgebers'; Record = @{ Name = 'WinMerge'; Publisher = 'Takashi Sawanaka' } }
        @{ Case = 'Notepad++ ohne Hersteller'; Record = @{ Name = 'Notepad++'; Publisher = $null } }
        @{ Case = 'unbekanntes Programm'; Record = @{ Name = 'Contoso Tool'; Publisher = 'Contoso' } }
    ) {
        $r = New-TestRecord @Record
        InModuleScope SoftwareInventory -Parameters @{ R = $r; C = $catalog } { Find-CatalogEntry -Record $R -Catalog $C } | Should -BeNullOrEmpty
    }
}
