using System.Net;
using System.Text;
using System.Text.Json;
using VpnHood.Core.Quic.Abstractions;
using VpnHood.Core.Quic.Droid;

namespace VpnHood.QuicTest;

// Exercises the REAL library (AndroidQuicClient -> IQuicConnection -> Stream) against the NetTester echo
// server, the same way VpnHood's ConnectorService uses it.
public static class LibraryEcho
{
    public static async Task<bool> Run(string ip, int controlPort, int quicPort, string domain,
        long up, long down, Action<string> log)
    {
        // 1) open a QUIC listener on the server
        var cfg = new { TcpPort = 0, HttpPort = 0, QuicPort = quicPort, HttpsPort = 0, Domain = domain, IsValidDomain = false };
        using (var http = new HttpClient { Timeout = TimeSpan.FromSeconds(10) }) {
            var content = new StringContent(JsonSerializer.Serialize(cfg), Encoding.UTF8, "application/json");
            var r = await http.PostAsync($"http://{ip}:{controlPort}/config", content);
            log($"POST /config -> {(int)r.StatusCode} {r.StatusCode}");
            r.EnsureSuccessStatusCode();
        }
        await Task.Delay(500);

        log($"AndroidQuicClient.IsSupported = {AndroidQuicClient.IsSupported}");
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));

        var client = new AndroidQuicClient();
        var options = new QuicClientConnectOptions {
            RemoteEndPoint = new IPEndPoint(IPAddress.Parse(ip), quicPort),
            TargetHost = domain,
            CertificateValidationCallback = (_, _, _, _) => true // echo server uses a throwaway cert
        };

        await using var conn = await client.ConnectAsync(options, cts.Token);
        log($"CONNECTED remote={conn.RemoteEndPoint}");

        await using var stream = await conn.OpenOutboundStreamAsync(cts.Token);

        // protocol: write upSize(Int64) + downSize(Int64) + up random bytes; then read down bytes
        var header = new byte[16];
        BitConverter.TryWriteBytes(header.AsSpan(0, 8), up);
        BitConverter.TryWriteBytes(header.AsSpan(8, 8), down);
        await stream.WriteAsync(header, cts.Token);

        var payload = new byte[(int)Math.Min(up, 64 * 1024)];
        new Random(1).NextBytes(payload);
        long sent = 0;
        while (sent < up) {
            var n = (int)Math.Min(payload.Length, up - sent);
            await stream.WriteAsync(payload.AsMemory(0, n), cts.Token);
            sent += n;
        }
        log($"uploaded {sent} bytes");

        long recv = 0;
        var rbuf = new byte[16 * 1024];
        while (recv < down) {
            var n = await stream.ReadAsync(rbuf, cts.Token);
            if (n == 0) break;
            recv += n;
        }
        log($"downloaded {recv}/{down}");
        return recv >= down;
    }
}
