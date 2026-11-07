# KI-Berater, nur lokale Server: Die Adresse wird aufgelöst und jede IP-Adresse eingeordnet. Erlaubt
# sind nur Loopback und private Netze (auch Link-Local); öffentliche oder nicht auflösbare Adressen
# werden abgelehnt. Externe Anbieter kommen später über Plugins, nicht über „eigene Adresse“.

function Resolve-AdvisorHost {
    # IP-Adressen eines Hosts; leer, wenn der Name nicht auflösbar ist. Eigene Funktion, damit Tests sie vorgeben können.
    param([string] $HostName)
    $ip = $null
    if ([System.Net.IPAddress]::TryParse($HostName, [ref] $ip)) { return $ip }
    try { [System.Net.Dns]::GetHostAddresses($HostName) }
    catch { Write-Verbose "Nicht auflösbar: $HostName ($($_.Exception.Message))" }
}

function Get-IpAddressNetwork {
    <#
    .SYNOPSIS
        Ordnet eine IP-Adresse ein: Loopback, Private oder Public.
    .DESCRIPTION
        Privat sind 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, Link-Local 169.254.0.0/16 sowie IPv6
        fc00::/7 (Unique Local) und fe80::/10 (Link-Local). IPv4-Adressen in IPv6 (::ffff:…) zählen wie IPv4.
        Alles andere, auch 0.0.0.0 und 100.64.0.0/10, gilt als öffentlich.
    #>
    param([System.Net.IPAddress] $Address)
    if ($Address.IsIPv4MappedToIPv6) { $Address = $Address.MapToIPv4() }
    if ([System.Net.IPAddress]::IsLoopback($Address)) { return 'Loopback' }
    $bytes = $Address.GetAddressBytes()
    if ($Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
        if ($bytes[0] -eq 10) { return 'Private' }
        if ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) { return 'Private' }
        if ($bytes[0] -eq 192 -and $bytes[1] -eq 168) { return 'Private' }
        if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { return 'Private' }
        return 'Public'
    }
    if ($Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
        if ($Address.IsIPv6LinkLocal) { return 'Private' }
        if (($bytes[0] -band 0xFE) -eq 0xFC) { return 'Private' }
    }
    'Public'
}
