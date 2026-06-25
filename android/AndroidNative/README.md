# VpnHood.Core.Quic.MsQuic.AndroidNative

A **self-contained native QUIC package for Android**. It ships:

1. The **`libmsquic.so`** per ABI (`arm64-v8a`, `x86_64`) — **built by CI and packed into the NuGet**
   (it flows into the consuming APK as `lib/<abi>/libmsquic.so`). The `.so` is **not committed**; it's
   git-ignored (`native/**/*.so`) and produced fresh on each build.
2. The **`Microsoft.Quic` C# P/Invoke bindings** — a committed, self-contained copy under `Bindings/`
   with **public** types, picked up by the SDK's default `.cs` globbing.

It has **no VpnHood dependencies**. Its whole job is to hide the native-linking complexity behind one
package reference.

## Consuming it

`VpnHood.Core.Quic.Android` references the published NuGet:

```xml
<PackageReference Include="VpnHood.Core.Quic.MsQuic.AndroidNative" Version="8.0.*" />
```

It gets both the bundled `.so` (transitively, into the APK) and the bindings. Because the binding types
are **public**, consumers use them directly — no `InternalsVisibleTo` needed.

## Publishing a new version

**Push to `main`** — GitHub Actions builds both ABIs, packs, and publishes `8.0.<run-number>` to
nuget.org (see [android/README.md](../README.md)). No manual version bump and no local build needed.

For a **local** pack (rare): build the `.so` first with `android/build-android.ps1`; the
`RefreshMsQuicNative` MSBuild target copies it into `native/<abi>/` before packing. Without a freshly
built `.so` the build fails on purpose — there is no committed binary to fall back on.

Only `arm64-v8a` and `x86_64` are produced; 32-bit ABIs are intentionally excluded.
