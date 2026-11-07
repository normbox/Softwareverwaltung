BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

Describe 'KI-Berater: Grenzen gegen Endlosschleifen (MaxTokens, TimeoutSeconds)' {
    BeforeEach {
        $settingsFile = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
        Mock -ModuleName SoftwareInventory Get-SettingsPath { $settingsFile }
        Mock -ModuleName SoftwareInventory Get-ServiceSecret { $null }
    }

    It 'beginnt mit 8192 Tokens und 300 Sekunden' {
        $s = Get-InventorySetting
        $s.Advisor.MaxTokens | Should -Be 8192
        $s.Advisor.TimeoutSeconds | Should -Be 300
    }

    It 'speichert beide Werte und gibt sie mit den Verbindungsdaten an die App' {
        Set-InventorySetting -AdvisorMaxTokens 2048 -AdvisorTimeoutSeconds 600 | Out-Null
        $s = Get-InventorySetting
        $s.Advisor.MaxTokens | Should -Be 2048
        $s.Advisor.TimeoutSeconds | Should -Be 600
        $c = Get-AdvisorConnection
        $c.MaxTokens | Should -Be 2048
        $c.TimeoutSeconds | Should -Be 600
    }

    It 'lehnt Werte außerhalb der Grenzen ab: <Name>' -ForEach @(
        @{ Name = 'MaxTokens 511'; Params = @{ AdvisorMaxTokens = 511 } }
        @{ Name = 'MaxTokens 32769'; Params = @{ AdvisorMaxTokens = 32769 } }
        @{ Name = 'TimeoutSeconds 29'; Params = @{ AdvisorTimeoutSeconds = 29 } }
        @{ Name = 'TimeoutSeconds 1801'; Params = @{ AdvisorTimeoutSeconds = 1801 } }
    ) {
        { Set-InventorySetting @Params } | Should -Throw
        (Get-InventorySetting).Advisor.MaxTokens | Should -Be 8192
    }

    It 'nimmt ungültige Werte aus der Datei nicht an' {
        '{"Advisor":{"MaxTokens":5,"TimeoutSeconds":"viel","ShareLevel":{"Local":3,"External":1}}}' | Set-Content -LiteralPath $settingsFile
        $s = Get-InventorySetting
        $s.Advisor.MaxTokens | Should -Be 8192
        $s.Advisor.TimeoutSeconds | Should -Be 300
    }

    It 'behält beide Werte, wenn andere Einstellungen gespeichert werden' {
        Set-InventorySetting -AdvisorMaxTokens 4096 | Out-Null
        Set-InventorySetting -LogRetentionDays 9 | Out-Null
        (Get-InventorySetting).Advisor.MaxTokens | Should -Be 4096
    }
}
