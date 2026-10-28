BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

Describe 'Split-CommandLine' {
    BeforeAll {
        $dir = Join-Path $TestDrive 'Mein Programm'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $exe = Join-Path $dir 'uninst.exe'
        Set-Content -LiteralPath $exe -Value 'x'
    }

    It 'löst einen Pfad in Anführungszeichen heraus' {
        $r = InModuleScope SoftwareInventory { Split-CommandLine '"C:\Program Files\Fabrikam\unins000.exe" /SILENT /NORESTART' }
        $r.FilePath | Should -Be 'C:\Program Files\Fabrikam\unins000.exe'
        $r.Arguments | Should -Be '/SILENT /NORESTART'
        $r.Error | Should -BeNullOrEmpty
    }

    It 'findet bei Pfaden ohne Anführungszeichen die vorhandene Datei trotz Leerzeichen' {
        $r = InModuleScope SoftwareInventory -Parameters @{ E = $exe } { Split-CommandLine "$E /S _?=x" }
        $r.FilePath | Should -Be $exe
        $r.Arguments | Should -Be '/S _?=x'
    }

    It 'sucht Programmnamen ohne Ordner nur in System32' {
        $r = InModuleScope SoftwareInventory { Split-CommandLine 'MsiExec.exe /X{11111111-2222-3333-4444-555555555555}' }
        $r.FilePath | Should -Be (Join-Path ([Environment]::GetFolderPath('System')) 'MsiExec.exe')
        $r.Arguments | Should -Be '/X{11111111-2222-3333-4444-555555555555}'
    }

    It 'löst Umgebungsvariablen nur im Pfad auf' {
        $r = InModuleScope SoftwareInventory { Split-CommandLine '"%ProgramFiles%\App\u.exe" /LOG=%TEMP%\u.log' }
        $r.FilePath | Should -Be "$env:ProgramFiles\App\u.exe"
        $r.Arguments | Should -Be '/LOG=%TEMP%\u.log'
    }

    It 'meldet leere, offene und programmlose Befehlszeilen als Fehler' -ForEach @(
        @{ Line = '' }, @{ Line = '"C:\App\u.exe /S' }, @{ Line = 'C:\App\script.bat /S' }
    ) {
        (InModuleScope SoftwareInventory -Parameters @{ L = $Line } { Split-CommandLine $L }).Error | Should -Not -BeNullOrEmpty
    }
}

Describe 'Resolve-UninstallCommand' {
    It 'lehnt Interpreter wie <Line> ab' -ForEach @(
        @{ Line = 'cmd.exe /c del C:\x' }
        @{ Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -File x.ps1' }
        @{ Line = 'rundll32.exe shell32.dll,Control_RunDLL' }
    ) {
        (InModuleScope SoftwareInventory -Parameters @{ L = $Line } { Resolve-UninstallCommand $L }).Error.Code | Should -Be 'CommandInterpreter'
    }

    It 'meldet fehlende Programmdateien' {
        (InModuleScope SoftwareInventory { Resolve-UninstallCommand '"C:\gibt-es-nicht\u.exe" /S' }).Error.Code | Should -Be 'CommandFileNotFound'
    }

    It 'akzeptiert vorhandene Programme' {
        $r = InModuleScope SoftwareInventory { Resolve-UninstallCommand 'MsiExec.exe /X{11111111-2222-3333-4444-555555555555}' }
        $r.Error | Should -BeNullOrEmpty
    }
}

Describe 'Test-UserWritablePath' {
    It 'erkennt Dateien im Benutzerprofil und in Temp als beschreibbar' {
        InModuleScope SoftwareInventory { Test-UserWritablePath "$env:TEMP\setup.exe" } | Should -BeTrue
        InModuleScope SoftwareInventory { Test-UserWritablePath "$env:USERPROFILE\Downloads\setup.exe" } | Should -BeTrue
    }

    It 'zählt Administratoren, SYSTEM und TrustedInstaller nicht als Benutzer (App läuft bereits erhöht)' {
        InModuleScope SoftwareInventory {
            Test-PrivilegedSid 'S-1-5-32-544' | Should -BeTrue
            Test-PrivilegedSid 'S-1-5-18' | Should -BeTrue
            Test-PrivilegedSid 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464' | Should -BeTrue
            Test-PrivilegedSid 'S-1-5-32-545' | Should -BeFalse
            Test-PrivilegedSid 'S-1-5-11' | Should -BeFalse
            Test-PrivilegedSid ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value) | Should -BeFalse
        }
    }

    It 'erkennt System32 als geschützt' {
        InModuleScope SoftwareInventory { Test-UserWritablePath (Join-Path ([Environment]::GetFolderPath('System')) 'msiexec.exe') } | Should -BeFalse
    }

    It 'wertet die ACL eines Ordners außerhalb des Profils aus' {
        # TestDrive liegt in Temp; deshalb einen Ordner auf demselben Laufwerk prüfen, der sicher beschreibbar ist.
        $root = Join-Path ([System.IO.Path]::GetPathRoot($PSScriptRoot)) "si-acl-test-$([guid]::NewGuid().ToString('N'))"
        try {
            New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'kein beschreibbares Laufwerk außerhalb des Profils'
            return
        }
        try {
            InModuleScope SoftwareInventory -Parameters @{ P = (Join-Path $root 'u.exe') } { Test-UserWritablePath $P } | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}
