using System.Net;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using Microsoft.Quic;
using static Microsoft.Quic.MsQuic;

namespace VpnHood.QuicTest;

// Minimal raw-msquic QUIC echo client (no System.Net.Quic). Validates the fork's C# P/Invoke
// bindings against the VpnHood.NetTester echo server. SAME code runs on desktop and Android.
// This is the logic that will become AndroidQuicClient/Connection/Stream.
public static class QuicEchoTester
{
    private static unsafe QUIC_API_TABLE* _api;
    private static Action<string> _log = _ => { };

    private sealed class ConnState
    {
        public readonly TaskCompletionSource Connected = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource Shutdown = new(TaskCreationOptions.RunContinuationsAsynchronously);
    }

    private sealed class StreamState
    {
        public long Received;
        public long Target;
        public readonly TaskCompletionSource DownDone = new(TaskCreationOptions.RunContinuationsAsynchronously);
    }

    /// <summary>POST the NetTester server config (opens a QUIC listener) then run one echo round-trip.</summary>
    public static bool Run(string controlIp, int controlPort, int quicPort, string domain,
        long up, long down, Action<string> log)
    {
        _log = log;
        try {
            log($"IsSupportedProbe: opening msquic...");
            PostConfig(controlIp, controlPort, quicPort, domain, log).GetAwaiter().GetResult();
            Thread.Sleep(500);
            var ok = RunEcho(controlIp, (ushort)quicPort, up, down, log);
            log(ok ? "ECHO TEST: SUCCESS" : "ECHO TEST: FAILED");
            return ok;
        }
        catch (Exception ex) {
            log($"ECHO TEST: EXCEPTION {ex.GetType().Name}: {ex.Message}\n{ex.StackTrace}");
            return false;
        }
    }

    private static async Task PostConfig(string ip, int controlPort, int quicPort, string domain, Action<string> log)
    {
        var cfg = new { TcpPort = 0, HttpPort = 0, QuicPort = quicPort, HttpsPort = 0, Domain = domain, IsValidDomain = false };
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
        var content = new StringContent(JsonSerializer.Serialize(cfg), Encoding.UTF8, "application/json");
        var r = await http.PostAsync($"http://{ip}:{controlPort}/config", content);
        log($"POST /config -> {(int)r.StatusCode} {r.StatusCode}");
        r.EnsureSuccessStatusCode();
    }

    private static unsafe bool RunEcho(string ip, ushort port, long up, long down, Action<string> log)
    {
        _api = MsQuic.Open();
        log("msquic API opened");
        QUIC_HANDLE* reg = null, config = null, conn = null, stream = null;
        var appName = Marshal.StringToCoTaskMemUTF8("vh-quic-test");
        var serverName = Marshal.StringToCoTaskMemUTF8(ip);
        GCHandle connGch = default, streamGch = default;
        try {
            var regConfig = new QUIC_REGISTRATION_CONFIG {
                AppName = (sbyte*)appName,
                ExecutionProfile = QUIC_EXECUTION_PROFILE.LOW_LATENCY
            };
            ThrowIfFailure(_api->RegistrationOpen(&regConfig, &reg));

            var alpn = stackalloc byte[2] { (byte)'h', (byte)'3' };
            var alpnBuf = new QUIC_BUFFER { Length = 2, Buffer = alpn };
            ThrowIfFailure(_api->ConfigurationOpen(reg, &alpnBuf, 1, null, 0, null, &config));

            var cred = new QUIC_CREDENTIAL_CONFIG {
                Type = QUIC_CREDENTIAL_TYPE.NONE,
                Flags = QUIC_CREDENTIAL_FLAGS.CLIENT | QUIC_CREDENTIAL_FLAGS.NO_CERTIFICATE_VALIDATION
            };
            ThrowIfFailure(_api->ConfigurationLoadCredential(config, &cred));
            log("configuration ready");

            var connState = new ConnState();
            connGch = GCHandle.Alloc(connState);
            ThrowIfFailure(_api->ConnectionOpen(reg, &ConnCallback, (void*)GCHandle.ToIntPtr(connGch), &conn));
            ThrowIfFailure(_api->ConnectionStart(conn, config, (ushort)QUIC_ADDRESS_FAMILY_UNSPEC, (sbyte*)serverName, port));
            log($"connecting to {ip}:{port}...");

            if (!connState.Connected.Task.Wait(TimeSpan.FromSeconds(15))) {
                log("CONNECT TIMEOUT");
                return false;
            }
            log("CONNECTED");

            var streamState = new StreamState { Target = down };
            streamGch = GCHandle.Alloc(streamState);
            ThrowIfFailure(_api->StreamOpen(conn, QUIC_STREAM_OPEN_FLAGS.NONE, &StreamCallback,
                (void*)GCHandle.ToIntPtr(streamGch), &stream));
            ThrowIfFailure(_api->StreamStart(stream, QUIC_STREAM_START_FLAGS.IMMEDIATE));

            var header = new byte[16];
            BitConverter.TryWriteBytes(header.AsSpan(0, 8), up);
            BitConverter.TryWriteBytes(header.AsSpan(8, 8), down);
            SendNative(stream, header, fin: false);

            var payload = new byte[(int)Math.Min(up, 64 * 1024)];
            new Random(1).NextBytes(payload);
            long sent = 0;
            while (sent < up) {
                var n = (int)Math.Min(payload.Length, up - sent);
                sent += n;
                SendNative(stream, payload.AsSpan(0, n), fin: sent >= up);
            }
            log($"uploaded {sent} bytes");

            if (!streamState.DownDone.Task.Wait(TimeSpan.FromSeconds(30))) {
                log($"DOWNLOAD TIMEOUT got={Interlocked.Read(ref streamState.Received)}/{down}");
                return false;
            }
            log($"downloaded {Interlocked.Read(ref streamState.Received)}/{down}");
            return Interlocked.Read(ref streamState.Received) >= down;
        }
        finally {
            if (stream != null) _api->StreamClose(stream);
            if (conn != null) _api->ConnectionClose(conn);
            if (config != null) _api->ConfigurationClose(config);
            if (reg != null) _api->RegistrationClose(reg);
            if (connGch.IsAllocated) connGch.Free();
            if (streamGch.IsAllocated) streamGch.Free();
            Marshal.FreeCoTaskMem(appName);
            Marshal.FreeCoTaskMem(serverName);
        }
    }

    private static unsafe void SendNative(QUIC_HANDLE* stream, ReadOnlySpan<byte> data, bool fin)
    {
        var total = (nuint)(sizeof(QUIC_BUFFER) + data.Length);
        var block = (byte*)NativeMemory.Alloc(total);
        var qb = (QUIC_BUFFER*)block;
        var dataPtr = block + sizeof(QUIC_BUFFER);
        data.CopyTo(new Span<byte>(dataPtr, data.Length));
        qb->Length = (uint)data.Length;
        qb->Buffer = dataPtr;
        var flags = fin ? QUIC_SEND_FLAGS.FIN : QUIC_SEND_FLAGS.NONE;
        var status = _api->StreamSend(stream, qb, 1, flags, block);
        if (StatusFailed(status)) {
            NativeMemory.Free(block);
            ThrowIfFailure(status);
        }
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvCdecl) })]
    private static unsafe int ConnCallback(QUIC_HANDLE* conn, void* ctx, QUIC_CONNECTION_EVENT* evt)
    {
        var state = (ConnState)GCHandle.FromIntPtr((IntPtr)ctx).Target!;
        switch (evt->Type) {
            case QUIC_CONNECTION_EVENT_TYPE.CONNECTED:
                _log("CONN: CONNECTED");
                state.Connected.TrySetResult();
                break;
            case QUIC_CONNECTION_EVENT_TYPE.SHUTDOWN_INITIATED_BY_TRANSPORT:
                _log($"CONN: transport shutdown status=0x{(uint)evt->SHUTDOWN_INITIATED_BY_TRANSPORT.Status:x} err=0x{evt->SHUTDOWN_INITIATED_BY_TRANSPORT.ErrorCode:x}");
                state.Connected.TrySetException(new Exception(
                    $"transport shutdown status=0x{(uint)evt->SHUTDOWN_INITIATED_BY_TRANSPORT.Status:x}"));
                break;
            case QUIC_CONNECTION_EVENT_TYPE.SHUTDOWN_INITIATED_BY_PEER:
                _log($"CONN: peer shutdown error=0x{evt->SHUTDOWN_INITIATED_BY_PEER.ErrorCode:x}");
                state.Connected.TrySetException(new Exception(
                    $"peer shutdown error=0x{evt->SHUTDOWN_INITIATED_BY_PEER.ErrorCode:x}"));
                break;
            case QUIC_CONNECTION_EVENT_TYPE.SHUTDOWN_COMPLETE:
                _log("CONN: shutdown complete");
                state.Shutdown.TrySetResult();
                break;
            default:
                _log($"CONN: evt {evt->Type}");
                break;
        }
        return QUIC_STATUS_SUCCESS;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvCdecl) })]
    private static unsafe int StreamCallback(QUIC_HANDLE* stream, void* ctx, QUIC_STREAM_EVENT* evt)
    {
        var state = (StreamState)GCHandle.FromIntPtr((IntPtr)ctx).Target!;
        switch (evt->Type) {
            case QUIC_STREAM_EVENT_TYPE.START_COMPLETE:
                _log($"STREAM: start complete status=0x{(uint)evt->START_COMPLETE.Status:x} id={evt->START_COMPLETE.ID}");
                break;
            case QUIC_STREAM_EVENT_TYPE.RECEIVE:
                var added = Interlocked.Add(ref state.Received, (long)evt->RECEIVE.TotalBufferLength);
                _log($"STREAM: recv {(long)evt->RECEIVE.TotalBufferLength} (total {added})");
                if (added >= state.Target)
                    state.DownDone.TrySetResult();
                break;
            case QUIC_STREAM_EVENT_TYPE.SEND_COMPLETE:
                _log($"STREAM: send complete canceled={evt->SEND_COMPLETE.Canceled}");
                if (evt->SEND_COMPLETE.ClientContext != null)
                    NativeMemory.Free(evt->SEND_COMPLETE.ClientContext);
                break;
            case QUIC_STREAM_EVENT_TYPE.PEER_SEND_SHUTDOWN:
                _log("STREAM: peer send shutdown");
                state.DownDone.TrySetResult();
                break;
            case QUIC_STREAM_EVENT_TYPE.PEER_SEND_ABORTED:
                _log($"STREAM: peer send ABORTED err=0x{evt->PEER_SEND_ABORTED.ErrorCode:x}");
                state.DownDone.TrySetResult();
                break;
            case QUIC_STREAM_EVENT_TYPE.PEER_RECEIVE_ABORTED:
                _log($"STREAM: peer recv ABORTED err=0x{evt->PEER_RECEIVE_ABORTED.ErrorCode:x}");
                break;
            case QUIC_STREAM_EVENT_TYPE.SHUTDOWN_COMPLETE:
                _log("STREAM: shutdown complete");
                state.DownDone.TrySetResult();
                break;
            default:
                _log($"STREAM: evt {evt->Type}");
                break;
        }
        return QUIC_STATUS_SUCCESS;
    }
}
