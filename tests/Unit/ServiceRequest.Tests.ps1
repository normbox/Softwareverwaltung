BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-EnabledSetting {
        param([string[]] $Service)
        $s = InModuleScope SoftwareInventory { New-DefaultSetting }
        foreach ($name in $Service) { $s.Services.$name = $true }
        $s
    }

    function New-HttpError {
        param([int] $Status, [hashtable] $Header = @{})
        $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode] $Status)
        foreach ($h in $Header.GetEnumerator()) { [void] $response.Headers.TryAddWithoutValidation($h.Key, [string] $h.Value) }
        $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new("Response status code does not indicate success: $Status", $response)
        [System.Management.Automation.ErrorRecord]::new($exception, 'WebCmdletWebResponseException', 'InvalidOperation', $null)
    }
}

Describe 'Invoke-ServiceRequest' {
    BeforeEach {
        $saved = @{ NVD = $env:NVD_API_KEY; GitHub = $env:GITHUB_TOKEN }
        $env:NVD_API_KEY = $null
        $env:GITHUB_TOKEN = $null
        $cache = Join-Path $TestDrive "cache-$([guid]::NewGuid())"
        Mock -ModuleName SoftwareInventory Get-CacheDirectory { $cache }
        Mock -ModuleName SoftwareInventory Start-Sleep { }
    }
    AfterEach {
        $env:NVD_API_KEY = $saved.NVD
        $env:GITHUB_TOKEN = $saved.GitHub
    }

    It 'fragt nichts ab, wenn der Dienst nicht aktiviert ist' {
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { throw 'darf nicht aufgerufen werden' }
        $err = $null
        try { InModuleScope SoftwareInventory -Parameters @{ S = (New-EnabledSetting) } { Invoke-ServiceRequest -Service GitHub -Uri 'https://api.github.com/x' -Setting $S } }
        catch { $err = $_ }
        $err.Exception.Data['Reason'] | Should -Be 'Disabled'
        Should -Invoke -ModuleName SoftwareInventory Invoke-WebRequest -Times 0 -Exactly
    }

    It 'unterdrückt die englischen Fortschrittsmeldungen von Invoke-WebRequest' {
        Mock -ModuleName SoftwareInventory Invoke-WebRequest {
            # Der Mock läuft im Bereich des Tests; die Einstellung steht im Aufrufer.
            $caller = Get-PSCallStack | Where-Object Command -EQ 'Invoke-ServiceRequest' | Select-Object -First 1
            $script:SeenProgressPreference = $caller.GetFrameVariables()['ProgressPreference'].Value
            [pscustomobject] @{ StatusCode = 200; Content = '{"a":1}' }
        }
        $script:SeenProgressPreference = $null
        InModuleScope SoftwareInventory -Parameters @{ S = (New-EnabledSetting GitHub) } { Invoke-ServiceRequest -Service GitHub -Uri 'https://api.github.com/p' -Setting $S } | Out-Null
        $script:SeenProgressPreference | Should -Be 'SilentlyContinue'
    }

    It 'liefert JSON und nutzt den Zwischenspeicher' {
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { [pscustomobject] @{ StatusCode = 200; Content = '{"tag_name":"v1.2.3","published_at":"2026-10-01T10:00:00Z"}' } }
        $s = New-EnabledSetting GitHub
        $first = InModuleScope SoftwareInventory -Parameters @{ S = $s } { Invoke-ServiceRequest -Service GitHub -Uri 'https://api.github.com/r' -CacheKey 'repo/x' -Setting $S }
        $second = InModuleScope SoftwareInventory -Parameters @{ S = $s } { Invoke-ServiceRequest -Service GitHub -Uri 'https://api.github.com/r' -CacheKey 'repo/x' -Setting $S }
        $first.tag_name | Should -Be 'v1.2.3'
        $second.published_at | Should -Be '2026-10-01T10:00:00Z'   # als Text, nicht in Ortszeit umgewandelt
        Should -Invoke -ModuleName SoftwareInventory Invoke-WebRequest -Times 1 -Exactly
    }

    It 'lädt neu, wenn der Zwischenspeicher abgelaufen ist' {
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { [pscustomobject] @{ StatusCode = 200; Content = '{"a":1}' } }
        $s = New-EnabledSetting KEV
        1..2 | ForEach-Object {
            InModuleScope SoftwareInventory -Parameters @{ S = $s } { Invoke-ServiceRequest -Service KEV -Uri 'https://x/kev' -CacheKey 'kev' -MaxAge ([timespan]::Zero) -Setting $S } | Out-Null
        }
        Should -Invoke -ModuleName SoftwareInventory Invoke-WebRequest -Times 2 -Exactly
    }

    It 'setzt Schlüssel nur als Header und nie in die URL oder den Zwischenspeicher' {
        $env:GITHUB_TOKEN = 'ghp_geheim789'
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { [pscustomobject] @{ StatusCode = 200; Content = '{"ok":true}' } }
        InModuleScope SoftwareInventory -Parameters @{ S = (New-EnabledSetting GitHub) } {
            Invoke-ServiceRequest -Service GitHub -Uri 'https://api.github.com/r' -CacheKey 'k' -Setting $S
        } | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Headers.Authorization -eq 'Bearer ghp_geheim789' -and "$Uri" -notmatch 'ghp_'
        }
        Get-ChildItem $cache -Recurse -File | Get-Content -Raw | Should -Not -Match 'ghp_geheim789'
    }

    It 'erkennt das Anfragelimit von GitHub' {
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { throw (New-HttpError 403 @{ 'X-RateLimit-Remaining' = '0' }) }
        $err = $null
        try { InModuleScope SoftwareInventory -Parameters @{ S = (New-EnabledSetting GitHub) } { Invoke-ServiceRequest -Service GitHub -Uri 'https://api.github.com/r' -Setting $S } }
        catch { $err = $_ }
        $err.Exception.Data['Reason'] | Should -Be 'RateLimit'
    }

    It 'meldet 404 als NotFound' {
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { throw (New-HttpError 404) }
        $err = $null
        try { InModuleScope SoftwareInventory -Parameters @{ S = (New-EnabledSetting GitHub) } { Invoke-ServiceRequest -Service GitHub -Uri 'https://api.github.com/r' -Setting $S } }
        catch { $err = $_ }
        $err.Exception.Data['Reason'] | Should -Be 'NotFound'
    }

    It 'enthält den Schlüssel nicht in Fehlermeldungen' {
        $env:NVD_API_KEY = 'nvd-geheim-456'
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('Verbindung abgebrochen, apiKey=nvd-geheim-456') }
        $err = $null
        try { InModuleScope SoftwareInventory -Parameters @{ S = (New-EnabledSetting NVD) } { Invoke-ServiceRequest -Service NVD -Uri 'https://nvd/x' -Setting $S } }
        catch { $err = $_ }
        $err.Exception.Data['Reason'] | Should -Be 'Network'
        $err.Exception.Message | Should -Not -Match 'nvd-geheim-456'
        $err.Exception.Message | Should -Match '\*\*\*'
    }

    It 'drosselt NVD ohne Schlüssel auf einen Abstand von sechs Sekunden' {
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { [pscustomobject] @{ StatusCode = 200; Content = '{}' } }
        InModuleScope SoftwareInventory -Parameters @{ S = (New-EnabledSetting NVD) } {
            $script:LastServiceCall.Remove('NVD')
            Invoke-ServiceRequest -Service NVD -Uri 'https://nvd/1' -Setting $S | Out-Null
            Invoke-ServiceRequest -Service NVD -Uri 'https://nvd/2' -Setting $S | Out-Null
        }
        Should -Invoke -ModuleName SoftwareInventory Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -gt 5000 -and $Milliseconds -le 6000 }
    }
}
