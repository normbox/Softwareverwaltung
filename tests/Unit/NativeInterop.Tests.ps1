BeforeAll {
    $script:ModuleRoot = Resolve-Path "$PSScriptRoot/../../src/SoftwareInventory"
    Import-Module $script:ModuleRoot -Force
}

Describe 'Fertig übersetzter Windows-Zugriff (SoftwareInventory.Native.dll)' {
    It 'lädt beide Typen aus lib\ über das Manifest, nicht zur Laufzeit übersetzt' {
        foreach ($name in 'SoftwareInventory.CredentialStore', 'SoftwareInventory.PipeInterop') {
            $type = $name -as [type]
            $type | Should -Not -BeNullOrEmpty -Because $name
            $type.Assembly.IsDynamic | Should -BeFalse
            $type.Assembly.Location | Should -BeLike '*\lib\SoftwareInventory.Native.dll'
        }
        (Import-PowerShellDataFile (Join-Path $script:ModuleRoot 'SoftwareInventory.psd1')).RequiredAssemblies |
            Should -Be @('lib\SoftwareInventory.Native.dll')
    }

    It 'enthält kein Add-Type mehr (im Constrained Language Mode gesperrt)' {
        # Über den Syntaxbaum, damit Kommentare und Texte mit „Add-Type“ nicht zählen.
        $found = foreach ($file in Get-ChildItem -LiteralPath $script:ModuleRoot -Recurse -Include '*.ps1', '*.psm1') {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $null, [ref] $null)
            $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Add-Type' }, $true) |
                ForEach-Object { "$($file.Name):$($_.Extent.StartLineNumber)" }
        }
        $found | Should -BeNullOrEmpty
    }

    It 'liefert die Prozess-ID der Gegenstelle einer Pipe' {
        $name = "softwareinventory-test-$([guid]::NewGuid().ToString('N'))"
        $server = [System.IO.Pipes.NamedPipeServerStream]::new($name, 'InOut', 1, 'Byte', 'Asynchronous')
        $client = [System.IO.Pipes.NamedPipeClientStream]::new('.', $name, 'InOut')
        try {
            $wait = $server.WaitForConnectionAsync()
            $client.Connect(5000)
            $wait.Wait(5000) | Should -BeTrue
            [uint32] $clientPid = 0
            [SoftwareInventory.PipeInterop]::GetNamedPipeClientProcessId($server.SafePipeHandle, [ref] $clientPid) | Should -BeTrue
            $clientPid | Should -Be $PID
        }
        finally {
            $client.Dispose()
            $server.Dispose()
        }
    }

    It 'lehnt zu lange Schlüssel mit Text aus der Sprachdatei ab, ohne etwas zu speichern' {
        $long = ConvertTo-SecureString ('x' * ([SoftwareInventory.CredentialStore]::MaxSecretLength + 1)) -AsPlainText -Force
        Mock -ModuleName SoftwareInventory Get-ServiceCredentialStatus { }
        { Set-ServiceCredential -Service NVD -Secret $long } | Should -Throw -ExpectedMessage '*zu lang*1280*'
        Should -Invoke -ModuleName SoftwareInventory Get-ServiceCredentialStatus -Times 0
    }

    It 'lehnt zu lange Schlüssel auch direkt in der DLL ab' {
        $long = ConvertTo-SecureString ('x' * ([SoftwareInventory.CredentialStore]::MaxSecretLength + 1)) -AsPlainText -Force
        { [SoftwareInventory.CredentialStore]::Write('SoftwareInventory-Test-nie-gespeichert', 'NVD', $long) } | Should -Throw
        [SoftwareInventory.CredentialStore]::Read('SoftwareInventory-Test-nie-gespeichert') | Should -BeNullOrEmpty
    }
}
