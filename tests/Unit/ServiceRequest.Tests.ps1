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
        # Nicht von Schlüsseln in der echten Anmeldeinformationsverwaltung abhängen
        Mock -ModuleName SoftwareInventory Read-StoredSecret { $null }
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

    It 'wartet bei 429 mit kurzem Retry-After einmal und wiederholt die Anfrage' {
        $script:Calls = 0
        Mock -ModuleName SoftwareInventory Invoke-WebRequest {
            $script:Calls++
            if ($script:Calls -eq 1) { throw (New-HttpError 429 @{ 'Retry-After' = '5' }) }
            [pscustomobject] @{ StatusCode = 200; Content = '{"ok":true}' }
        }
        $r = InModuleScope SoftwareInventory -Parameters @{ S = (New-EnabledSetting CIRCL) } { Invoke-ServiceRequest -Service CIRCL -Uri 'https://circl/x' -Setting $S }
        $r.ok | Should -BeTrue
        $script:Calls | Should -Be 2
        Should -Invoke -ModuleName SoftwareInventory Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 5 }
    }

    It 'wiederholt bei 429 höchstens einmal und meldet dann das Anfragelimit' {
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { throw (New-HttpError 429 @{ 'Retry-After' = '2' }) }
        $err = $null
        try { InModuleScope SoftwareInventory -Parameters @{ S = (New-EnabledSetting CIRCL) } { Invoke-ServiceRequest -Service CIRCL -Uri 'https://circl/x' -Setting $S } }
        catch { $err = $_ }
        $err.Exception.Data['Reason'] | Should -Be 'RateLimit'
        Should -Invoke -ModuleName SoftwareInventory Invoke-WebRequest -Times 2 -Exactly
    }

    It 'wartet bei langem Retry-After nicht, sondern nimmt den veralteten Zwischenspeicher' {
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { throw (New-HttpError 429 @{ 'Retry-After' = '120' }) }
        $r = InModuleScope SoftwareInventory -Parameters @{ S = (New-EnabledSetting CIRCL) } {
            $file = Get-ServiceCacheFile -Service CIRCL -CacheKey 'k'
            Write-ServiceCache -Path $file -Content '{"alt":1}'
            Invoke-ServiceRequest -Service CIRCL -Uri 'https://circl/x' -CacheKey 'k' -MaxAge ([timespan]::Zero) -Setting $S
        }
        $r.alt | Should -Be 1
        Should -Invoke -ModuleName SoftwareInventory Invoke-WebRequest -Times 1 -Exactly
        Should -Invoke -ModuleName SoftwareInventory Start-Sleep -Times 0 -Exactly -ParameterFilter { $Seconds -gt 0 }
    }

    It 'liest Retry-After auch als HTTP-Datum' {
        $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode] 429)
        $response.Headers.RetryAfter = [System.Net.Http.Headers.RetryConditionHeaderValue]::new([datetimeoffset]::UtcNow.AddSeconds(30))
        $seconds = InModuleScope SoftwareInventory -Parameters @{ R = $response } { Get-RetryAfterSecond $R }
        $seconds | Should -BeGreaterOrEqual 28
        $seconds | Should -BeLessOrEqual 31
        InModuleScope SoftwareInventory { Get-RetryAfterSecond ([System.Net.Http.HttpResponseMessage]::new(429)) } | Should -BeNullOrEmpty
    }

    It 'schickt den CIRCL-Schlüssel als X-API-KEY und nennt eine Kontakt-URL' {
        $savedCircl = $env:CIRCL_API_KEY
        $env:CIRCL_API_KEY = 'circl-test-key'
        try {
            Mock -ModuleName SoftwareInventory Invoke-WebRequest { [pscustomobject] @{ StatusCode = 200; Content = '{}' } }
            InModuleScope SoftwareInventory -Parameters @{ S = (New-EnabledSetting CIRCL) } { Invoke-ServiceRequest -Service CIRCL -Uri 'https://circl/x' -Setting $S } | Out-Null
            Should -Invoke -ModuleName SoftwareInventory Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Headers['X-API-KEY'] -eq 'circl-test-key' -and $Headers['User-Agent'] -match '\(\+https://github\.com/' -and -not $Headers.ContainsKey('apiKey')
            }
        }
        finally { $env:CIRCL_API_KEY = $savedCircl }
    }

    It 'drosselt CIRCL ohne Schlüssel auf drei Sekunden Abstand' {
        $savedCircl = $env:CIRCL_API_KEY
        $env:CIRCL_API_KEY = $null
        try {
            Mock -ModuleName SoftwareInventory Get-ServiceSecret { $null }
            Mock -ModuleName SoftwareInventory Invoke-WebRequest { [pscustomobject] @{ StatusCode = 200; Content = '{}' } }
            InModuleScope SoftwareInventory -Parameters @{ S = (New-EnabledSetting CIRCL) } {
                $script:LastServiceCall.Remove('CIRCL')
                Invoke-ServiceRequest -Service CIRCL -Uri 'https://circl/1' -Setting $S | Out-Null
                Invoke-ServiceRequest -Service CIRCL -Uri 'https://circl/2' -Setting $S | Out-Null
            }
            Should -Invoke -ModuleName SoftwareInventory Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -gt 2000 -and $Milliseconds -le 3000 }
        }
        finally { $env:CIRCL_API_KEY = $savedCircl }
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
