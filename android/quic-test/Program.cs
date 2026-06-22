using System.Net;
using VpnHood.QuicTest;

// Desktop runner for the shared raw-msquic echo tester (same code path as the Android app).
// Usage: quic-test <controlIp:port> <quicPort> [domain] [upBytes] [downBytes]
var control = args.Length > 0 ? args[0] : "15.204.89.227:4040";
var quicPort = args.Length > 1 ? int.Parse(args[1]) : 4041;
var domain = args.Length > 2 ? args[2] : "test.vpnhood.com";
long up = args.Length > 3 ? long.Parse(args[3]) : 64 * 1024;
long down = args.Length > 4 ? long.Parse(args[4]) : 64 * 1024;
var controlEp = IPEndPoint.Parse(control);

var ok = QuicEchoTester.Run(controlEp.Address.ToString(), controlEp.Port, quicPort, domain, up, down, Console.WriteLine);
return ok ? 0 : 2;
