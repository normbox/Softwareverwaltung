BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

Describe 'API-Schlüssel' {
    BeforeEach {
        $saved = @{ NVD = $env:NVD_API_KEY; GitHub = $env:GITHUB_TOKEN }
        # Eigener Präfix, damit echte Einträge des Entwicklers unberührt bleiben.
        $prefix = "SoftwareInventory-Test-$([guid]::NewGuid())"
        InModuleScope SoftwareInventory -Parameters @{ Prefix = $prefix } {
            param($Prefix)
            $script:SavedCredentialPrefix = $script:CredentialPrefix
            $script:CredentialPrefix = $Prefix
        }
    }
    AfterEach {
        foreach ($service in 'NVD', 'GitHub', 'Advisor') {
            InModuleScope SoftwareInventory -Parameters @{ Service = $service } {
                param($Service)
                Initialize-CredentialInterop
                [void] [SoftwareInventory.CredentialStore]::Delete((Get-CredentialTarget $Service))
            }
        }
        InModuleScope SoftwareInventory { $script:CredentialPrefix = $script:SavedCredentialPrefix }
        $env:NVD_API_KEY = $saved.NVD
        $env:GITHUB_TOKEN = $saved.GitHub
    }

    It 'liest Schlüssel aus Umgebungsvariablen und ist ohne sie leer' {
        $env:NVD_API_KEY = '  nvd-test-123  '
        $env:GITHUB_TOKEN = $null
        InModuleScope SoftwareInventory { Get-ServiceSecret -Service NVD } | Should -Be 'nvd-test-123'
        InModuleScope SoftwareInventory { Get-ServiceSecret -Service GitHub } | Should -BeNullOrEmpty
    }

    It 'speichert, liest und löscht Schlüssel in der Anmeldeinformationsverwaltung' {
        $env:GITHUB_TOKEN = $null
        $status = Set-ServiceCredential -Service GitHub -Secret (ConvertTo-SecureString 'ghp_gespeichert1' -AsPlainText -Force)
        $status.Stored | Should -BeTrue
        $status.Source | Should -Be 'CredentialManager'
        InModuleScope SoftwareInventory { Get-ServiceSecret -Service GitHub } | Should -Be 'ghp_gespeichert1'

        $status = Remove-ServiceCredential -Service GitHub
        $status.Stored | Should -BeFalse
        $status.Source | Should -BeNullOrEmpty
        InModuleScope SoftwareInventory { Get-ServiceSecret -Service GitHub } | Should -BeNullOrEmpty
    }

    It 'bevorzugt die Anmeldeinformationsverwaltung vor der Umgebungsvariablen' {
        $env:NVD_API_KEY = 'nvd-aus-variable'
        Set-ServiceCredential -Service NVD -Secret (ConvertTo-SecureString 'nvd-gespeichert' -AsPlainText -Force) | Out-Null
        InModuleScope SoftwareInventory { Get-ServiceSecret -Service NVD } | Should -Be 'nvd-gespeichert'
        $status = Get-ServiceCredentialStatus -Service NVD
        $status.Source | Should -Be 'CredentialManager'
        $status.EnvironmentSet | Should -BeTrue

        Remove-ServiceCredential -Service NVD | Out-Null
        InModuleScope SoftwareInventory { Get-ServiceSecret -Service NVD } | Should -Be 'nvd-aus-variable'
        (Get-ServiceCredentialStatus -Service NVD).Source | Should -Be 'Environment'
    }

    It 'gibt im Status nie den Schlüssel aus' {
        Set-ServiceCredential -Service NVD -Secret (ConvertTo-SecureString 'nvd-nie-zeigen' -AsPlainText -Force) | Out-Null
        Get-ServiceCredentialStatus | ConvertTo-Json | Should -Not -Match 'nvd-nie-zeigen'
    }

    It 'lehnt leere Schlüssel ab und löscht fehlende Einträge ohne Fehler' {
        { Set-ServiceCredential -Service NVD -Secret ([securestring]::new()) } | Should -Throw
        { Remove-ServiceCredential -Service NVD } | Should -Not -Throw
    }

    It 'entfernt Schlüssel aus beiden Ablagen aus Texten' {
        $env:NVD_API_KEY = 'nvd-geheim-456'
        $env:GITHUB_TOKEN = 'ghp_geheim789'
        Set-ServiceCredential -Service NVD -Secret (ConvertTo-SecureString 'nvd-gespeichert-000' -AsPlainText -Force) | Out-Null
        $text = InModuleScope SoftwareInventory { Protect-SecretText 'apiKey: nvd-geheim-456, Authorization: Bearer ghp_geheim789, alt: nvd-gespeichert-000' }
        $text | Should -Be 'apiKey: ***, Authorization: Bearer ***, alt: ***'
    }

    It 'lässt Texte ohne Schlüssel unverändert' {
        $env:NVD_API_KEY = $null
        $env:GITHUB_TOKEN = $null
        InModuleScope SoftwareInventory { Protect-SecretText 'nichts Geheimes' } | Should -Be 'nichts Geheimes'
        InModuleScope SoftwareInventory { Protect-SecretText $null } | Should -BeNullOrEmpty
    }
}

Describe 'API-Schlüssel für den KI-Berater' {
    BeforeEach {
        $saved = $env:SOFTWAREINVENTORY_ADVISOR_KEY
        $prefix = "SoftwareInventory-Test-$([guid]::NewGuid())"
        InModuleScope SoftwareInventory -Parameters @{ Prefix = $prefix } { param($Prefix); $script:SavedCredentialPrefix = $script:CredentialPrefix; $script:CredentialPrefix = $Prefix }
    }
    AfterEach {
        InModuleScope SoftwareInventory { Initialize-CredentialInterop; [void] [SoftwareInventory.CredentialStore]::Delete((Get-CredentialTarget Advisor)); $script:CredentialPrefix = $script:SavedCredentialPrefix }
        $env:SOFTWAREINVENTORY_ADVISOR_KEY = $saved
    }

    It 'speichert den Schlüssel, maskiert ihn und gibt ihn im Status nie aus' {
        $env:SOFTWAREINVENTORY_ADVISOR_KEY = $null
        (Set-ServiceCredential -Service Advisor -Secret (ConvertTo-SecureString 'sk-unsloth-geheim' -AsPlainText -Force)).Stored | Should -BeTrue
        InModuleScope SoftwareInventory { Get-ServiceSecret -Service Advisor } | Should -Be 'sk-unsloth-geheim'
        InModuleScope SoftwareInventory { Protect-SecretText 'Bearer sk-unsloth-geheim' } | Should -Be 'Bearer ***'
        Get-ServiceCredentialStatus | ConvertTo-Json | Should -Not -Match 'sk-unsloth-geheim'
        (Get-ServiceCredentialStatus -Service Advisor).EnvironmentVariable | Should -Be 'SOFTWAREINVENTORY_ADVISOR_KEY'
    }
}
