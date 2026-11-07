using System.Net;
using System.Net.Http;
using System.Net.Sockets;

namespace Softwareverwaltung.App.Advisor;

/// <summary>
/// HTTP-Verbindungen nur zu lokalen Adressen. Der Name wird hier selbst aufgelöst, jede Adresse geprüft und
/// nur zu geprüften Adressen verbunden; danach wird die tatsächlich verbundene Gegenstelle noch einmal geprüft.
/// So hilft auch ein Name nicht, der zwischen Prüfung und Verbindung auf eine andere Adresse zeigt (DNS-Rebinding).
/// TLS bleibt unverändert: SocketsHttpHandler baut TLS über diesen Stream mit dem Hostnamen der Anfrage auf
/// (SNI und Zertifikatsprüfung gegen den Namen); SslOptions werden nicht angefasst.
/// Keine Weiterleitungen, kein System-Proxy (er würde lokale Anfragen ins Netz umleiten), keine Cookies.
/// </summary>
public static class LocalOnlyHttp
{
    public delegate Task<IPAddress[]> Resolver(string host, CancellationToken cancellationToken);

    public static SocketsHttpHandler CreateHandler(Resolver? resolve = null) => new()
    {
        AllowAutoRedirect = false,
        UseProxy = false,
        UseCookies = false,
        ConnectTimeout = TimeSpan.FromSeconds(10),
        // Neue Verbindungen nach kurzer Zeit, damit jede Verbindung erneut geprüft wird
        PooledConnectionLifetime = TimeSpan.FromMinutes(2),
        ConnectCallback = (context, cancellationToken) => ConnectAsync(context.DnsEndPoint, resolve ?? ResolveAsync, cancellationToken),
    };

    public static async ValueTask<Stream> ConnectAsync(DnsEndPoint endPoint, Resolver resolve, CancellationToken cancellationToken)
    {
        var host = endPoint.Host.Trim('[', ']');
        var addresses = await resolve(host, cancellationToken).ConfigureAwait(false);
        if (addresses.Length == 0)
        {
            throw new AdvisorException("AdvisorEndpointUnresolvable", host);
        }
        var foreign = addresses.Where(a => !LocalAddressPolicy.IsLocal(a)).ToList();
        if (foreign.Count > 0)
        {
            throw new AdvisorException("AdvisorEndpointNotLocal", host, string.Join(", ", foreign));
        }

        var socket = new Socket(SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
        try
        {
            await socket.ConnectAsync(addresses, endPoint.Port, cancellationToken).ConfigureAwait(false);
            if (socket.RemoteEndPoint is not IPEndPoint remote || !LocalAddressPolicy.IsLocal(remote.Address))
            {
                throw new AdvisorException("AdvisorEndpointNotLocal", host, socket.RemoteEndPoint?.ToString() ?? "?");
            }
            return new NetworkStream(socket, ownsSocket: true);
        }
        catch
        {
            socket.Dispose();
            throw;
        }
    }

    /// <summary>IP-Literal direkt, sonst DNS; nicht auflösbar = leer.</summary>
    public static async Task<IPAddress[]> ResolveAsync(string host, CancellationToken cancellationToken)
    {
        if (IPAddress.TryParse(host, out var literal))
        {
            return [literal];
        }
        try
        {
            return await Dns.GetHostAddressesAsync(host, cancellationToken).ConfigureAwait(false);
        }
        catch (SocketException)
        {
            return [];
        }
        catch (ArgumentException)
        {
            return [];
        }
    }
}
