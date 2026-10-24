BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

Describe 'API-Schlüssel' {
    BeforeEach {
        $saved = @{ NVD = $env:NVD_API_KEY; GitHub = $env:GITHUB_TOKEN }
    }
    AfterEach {
        $env:NVD_API_KEY = $saved.NVD
        $env:GITHUB_TOKEN = $saved.GitHub
    }

    It 'liest Schlüssel aus Umgebungsvariablen und ist ohne sie leer' {
        $env:NVD_API_KEY = '  nvd-test-123  '
        $env:GITHUB_TOKEN = $null
        InModuleScope SoftwareInventory { Get-ServiceSecret -Service NVD } | Should -Be 'nvd-test-123'
        InModuleScope SoftwareInventory { Get-ServiceSecret -Service GitHub } | Should -BeNullOrEmpty
    }

    It 'entfernt Schlüssel aus Texten' {
        $env:NVD_API_KEY = 'nvd-geheim-456'
        $env:GITHUB_TOKEN = 'ghp_geheim789'
        $text = InModuleScope SoftwareInventory { Protect-SecretText 'apiKey: nvd-geheim-456, Authorization: Bearer ghp_geheim789' }
        $text | Should -Be 'apiKey: ***, Authorization: Bearer ***'
    }

    It 'lässt Texte ohne Schlüssel unverändert' {
        $env:NVD_API_KEY = $null
        $env:GITHUB_TOKEN = $null
        InModuleScope SoftwareInventory { Protect-SecretText 'nichts Geheimes' } | Should -Be 'nichts Geheimes'
        InModuleScope SoftwareInventory { Protect-SecretText $null } | Should -BeNullOrEmpty
    }
}
