using System.Net;
using System.Net.Sockets;

namespace Softwareverwaltung.App.Advisor;

public enum AdvisorNetwork
{
    Loopback,
    Private,
    Public,
}

/// <summary>
/// Dieselbe Regel wie Get-IpAddressNetwork im Modul, für die Prüfung beim Verbinden (ohne PowerShell, damit
/// sie nicht an der Sperre eines laufenden Scans hängt). Beide prüfen gegen tests/Data/advisor-address-cases.json.
/// Privat: 10/8, 172.16/12, 192.168/16, 169.254/16, fc00::/7, fe80::/10; IPv4 in IPv6 zählt wie IPv4.
/// </summary>
public static class LocalAddressPolicy
{
    public static AdvisorNetwork Classify(IPAddress address)
    {
        if (address.IsIPv4MappedToIPv6)
        {
            address = address.MapToIPv4();
        }
        if (IPAddress.IsLoopback(address))
        {
            return AdvisorNetwork.Loopback;
        }
        var b = address.GetAddressBytes();
        if (address.AddressFamily == AddressFamily.InterNetwork)
        {
            var isPrivate = b[0] == 10
                || (b[0] == 172 && b[1] >= 16 && b[1] <= 31)
                || (b[0] == 192 && b[1] == 168)
                || (b[0] == 169 && b[1] == 254);
            return isPrivate ? AdvisorNetwork.Private : AdvisorNetwork.Public;
        }
        if (address.AddressFamily == AddressFamily.InterNetworkV6 && (address.IsIPv6LinkLocal || (b[0] & 0xFE) == 0xFC))
        {
            return AdvisorNetwork.Private;
        }
        return AdvisorNetwork.Public;
    }

    public static bool IsLocal(IPAddress address) => Classify(address) != AdvisorNetwork.Public;
}
