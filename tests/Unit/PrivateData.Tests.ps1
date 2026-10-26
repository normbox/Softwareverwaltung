BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

Describe 'Protect-PrivateText' {
    BeforeEach {
        Mock -ModuleName SoftwareInventory Get-PrivateIdentity {
            [pscustomobject] @{ UserProfile = 'C:\Users\normb'; UserName = 'normb'; ComputerName = 'NORM-PC'; Domain = 'FIRMA' }
        }
        Mock -ModuleName SoftwareInventory Protect-SecretText { $Text }
        function Protect { param($Text) InModuleScope SoftwareInventory -Parameters @{ T = $Text } { Protect-PrivateText $T } }
    }

    It 'ersetzt das eigene Profil in <Case>' -TestCases @(
        @{ Case = 'Windows-Pfad'; Text = 'C:\Users\normb\AppData\Local\Programs\cursor\Cursor.exe'; Expected = '%USERPROFILE%\AppData\Local\Programs\cursor\Cursor.exe' }
        @{ Case = 'JSON mit doppelten Backslashes'; Text = '{"Path":"C:\\Users\\normb\\Tools\\x.exe"}'; Expected = '{"Path":"%USERPROFILE%\\Tools\\x.exe"}' }
        @{ Case = 'Schrägstrichen'; Text = 'c:/users/NORMB/Downloads'; Expected = '%USERPROFILE%/Downloads' }
        @{ Case = 'Profil allein'; Text = 'Ort: C:\Users\normb.'; Expected = 'Ort: %USERPROFILE%.' }
    ) {
        Protect $Text | Should -Be $Expected
    }

    It 'ersetzt Profile anderer Benutzer, lässt Public und Default stehen' {
        Protect 'C:\Users\anna\Desktop\a.exe; C:\Users\Public\b.exe; D:\Benutzer\max\c.exe' |
            Should -Be 'C:\Users\%OTHERUSER%\Desktop\a.exe; C:\Users\Public\b.exe; D:\Benutzer\%OTHERUSER%\c.exe'
    }

    It 'ersetzt Benutzername, Rechnername und Domäne nur als ganzes Wort' {
        Protect 'Angemeldet: FIRMA\normb an NORM-PC; normbox bleibt' |
            Should -Be 'Angemeldet: %USERDOMAIN%\%USERNAME% an %COMPUTERNAME%; normbox bleibt'
    }

    It 'bereinigt Pfade auf Wechseldatenträgern und nicht erreichbaren Laufwerken: <Case>' -TestCases @(
        @{ Case = 'eigenes Profil auf USB-Stick'; Text = 'F:\Users\normb\PortableApps\tool.exe'; Expected = 'F:\Users\%USERNAME%\PortableApps\tool.exe' }
        @{ Case = 'Benutzername als Ordner auf USB-Stick'; Text = 'G:\normb\Tools\tool.exe'; Expected = 'G:\%USERNAME%\Tools\tool.exe' }
        @{ Case = 'fremdes Profil auf nicht erreichbarem Laufwerk'; Text = 'X:\Users\anna\Desktop\a.exe'; Expected = 'X:\Users\%OTHERUSER%\Desktop\a.exe' }
        @{ Case = 'Netzlaufwerk mit Rechnername'; Text = '\\NORM-PC\Freigabe\normb\b.exe'; Expected = '\\%COMPUTERNAME%\Freigabe\%USERNAME%\b.exe' }
        @{ Case = 'JSON eines Spurentreffers'; Text = '{"FilePath":"F:\\Users\\normb\\x.exe","Flags":["PathUnreachable"]}'; Expected = '{"FilePath":"F:\\Users\\%USERNAME%\\x.exe","Flags":["PathUnreachable"]}' }
    ) {
        Protect $Text | Should -Be $Expected
    }

    It 'lässt Texte ohne persönliche Angaben unverändert' {
        Protect '7-Zip 26.05 (x64), C:\Program Files\7-Zip' | Should -Be '7-Zip 26.05 (x64), C:\Program Files\7-Zip'
        Protect $null | Should -BeNullOrEmpty
    }

    It 'entfernt auch API-Schlüssel' {
        Mock -ModuleName SoftwareInventory Protect-SecretText { $Text.Replace('geheim123', '***') }
        Protect 'key=geheim123' | Should -Be 'key=***'
    }
}
