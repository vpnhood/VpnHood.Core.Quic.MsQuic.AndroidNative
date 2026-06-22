using Android.App;
using Android.OS;
using Android.Widget;

namespace VpnHood.QuicTest;

[Activity(Label = "QuicTest", MainLauncher = true)]
public class MainActivity : Activity
{
    private const string Tag = "QUICTEST";
    private TextView _text;

    protected override void OnCreate(Bundle savedInstanceState)
    {
        base.OnCreate(savedInstanceState);

        var scroll = new ScrollView(this);
        _text = new TextView(this) { Text = "QUIC library echo test (AndroidQuicClient)...\n" };
        scroll.AddView(_text);
        SetContentView(scroll);

        new Thread(() => {
            void Log(string m)
            {
                Android.Util.Log.Info(Tag, m);
                RunOnUiThread(() => _text.Text += m + "\n");
            }

            try {
                var ok = LibraryEcho.Run(
                    ip: "15.204.89.227", controlPort: 4040, quicPort: 4041,
                    domain: "test.vpnhood.com", up: 64 * 1024, down: 64 * 1024, log: Log)
                    .GetAwaiter().GetResult();
                Log(ok ? ">>> RESULT: SUCCESS" : ">>> RESULT: FAILED");
            }
            catch (Exception ex) {
                Android.Util.Log.Error(Tag, Java.Lang.Throwable.FromException(ex), "unhandled");
                RunOnUiThread(() => _text.Text += $">>> UNHANDLED {ex.GetType().Name}: {ex.Message}\n{ex.StackTrace}\n");
            }
        }) { IsBackground = true }.Start();
    }
}
