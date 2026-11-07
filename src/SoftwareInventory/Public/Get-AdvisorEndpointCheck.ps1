function Get-AdvisorEndpointCheck {
    <#
    .SYNOPSIS
        Prüft, ob eine Adresse für den KI-Berater ein lokaler Server ist.
    .DESCRIPTION
        Der Hostname wird aufgelöst; jede IP-Adresse muss Loopback oder privat sein (10/8, 172.16/12,
        192.168/16, Link-Local 169.254/16, fc00::/7, fe80::/10). Geprüft wird die aufgelöste Adresse,
        nicht nur der Name. Ok ist $false bei ungültiger, nicht auflösbarer oder öffentlicher Adresse.
        http im privaten Netz ist erlaubt, Unencrypted ist dann $true und Message nennt den Hinweis.
        Die App prüft beim Verbinden zusätzlich die tatsächlich verbundene Adresse.
        Message-Codes: AdvisorEndpointInvalid, AdvisorEndpointUnresolvable, AdvisorEndpointNotLocal,
        AdvisorEndpointUnencrypted (nur Hinweis).
    .OUTPUTS
        Endpoint, Host, Addresses, Network (Loopback, Private, Public, Unresolvable, Invalid), Ok,
        Unencrypted, Message (Code, Args, Text oder $null).
    .EXAMPLE
        Get-AdvisorEndpointCheck -Endpoint 'http://192.168.1.20:11434/v1'
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.AdvisorEndpointCheck')]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Endpoint)

    $result = [ordered]@{
        PSTypeName = 'SoftwareInventory.AdvisorEndpointCheck'
        Endpoint = $Endpoint; Host = $null; Addresses = [string[]] @(); Network = 'Invalid'
        Ok = $false; Unencrypted = $false; Message = $null
    }
    if (-not (Test-AdvisorEndpoint $Endpoint)) {
        $result.Message = New-InventoryMessage AdvisorEndpointInvalid $Endpoint
        return [pscustomobject] $result
    }
    $uri = [uri] $Endpoint
    $result.Host = $uri.DnsSafeHost
    $addresses = @(Resolve-AdvisorHost $uri.DnsSafeHost) | Where-Object { $_ }
    $result.Addresses = [string[]] @($addresses | ForEach-Object { $_.ToString() })
    if (-not $addresses) {
        $result.Network = 'Unresolvable'
        $result.Message = New-InventoryMessage AdvisorEndpointUnresolvable $uri.DnsSafeHost
        return [pscustomobject] $result
    }
    $networks = @($addresses | ForEach-Object { Get-IpAddressNetwork $_ })
    if ('Public' -in $networks) {
        $result.Network = 'Public'
        $public = @($addresses | Where-Object { (Get-IpAddressNetwork $_) -eq 'Public' } | ForEach-Object { $_.ToString() })
        $result.Message = New-InventoryMessage AdvisorEndpointNotLocal $uri.DnsSafeHost, ($public -join ', ')
        return [pscustomobject] $result
    }
    $result.Network = if ($networks | Where-Object { $_ -ne 'Loopback' }) { 'Private' } else { 'Loopback' }
    $result.Ok = $true
    if ($result.Network -eq 'Private' -and $uri.Scheme -eq 'http') {
        $result.Unencrypted = $true
        $result.Message = New-InventoryMessage AdvisorEndpointUnencrypted $uri.DnsSafeHost
    }
    [pscustomobject] $result
}
