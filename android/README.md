# VpnHood — msquic for Android (native)

A **fork of [microsoft/msquic](https://github.com/microsoft/msquic)** that cross-compiles msquic for
Android (`arm64-v8a`, `x86_64`) with OpenSSL as the TLS backend, and publishes it as the NuGet package
**`VpnHood.Core.Quic.MsQuic.AndroidNative`** (the native `libmsquic.so` + the `Microsoft.Quic` C# bindings).

All VpnHood-specific code lives under this `android/` directory so merges from upstream msquic stay
conflict-free. The only changes outside it are the few source patches the Android/OpenSSL build needs
(`CMakeLists.txt`, `submodules/CMakeLists.txt`, `submodules/patches/`).

## How it's built & published — the normal path

**GitHub Actions builds and publishes on every push to `main`. No local toolchain is required.**
[`.github/workflows/android-publish.yml`](../.github/workflows/android-publish.yml) cross-compiles both
ABIs on `ubuntu-latest`, packs the NuGet, and pushes it to nuget.org as **`8.0.<run-number>`**
(auto-incrementing). Consumers float on `8.0.*` (or pin a version) and restore the newest build.

- The native `.so` is **not committed** — it is built fresh by CI and packed into the package
  (`native/**/*.so` is git-ignored).
- `NUGET_API_KEY` is an **organization secret** on the `vpnhood` GitHub org.

**To ship a new native build: push to `main`.** That's the whole release process.

## Building locally (optional)

Only needed to iterate on the native `.so` without a CI round-trip — for example testing an msquic/OpenSSL
change before pushing. See **[DEV-GUIDE.md](DEV-GUIDE.md)** for prerequisites (Windows, NDK, Strawberry
Perl, …) and how the build works under the hood.

```powershell
./android/build-android.ps1          # Release, both arches -> android/artifacts/ (git-ignored)
```

## Related docs

| Doc | Purpose |
|-----|---------|
| [AndroidNative/README.md](AndroidNative/README.md) | What the package ships and how `VpnHood.Core.Quic.Android` consumes it |
| [DEV-GUIDE.md](DEV-GUIDE.md) | Local Windows build, the key source patches, and upstream-merge steps |

## Fresh clone & remotes

```bash
git clone --recurse-submodules https://github.com/vpnhood/VpnHood.Core.Quic.MsQuic.AndroidNative.git
```

| name       | url                                                      |
|------------|----------------------------------------------------------|
| `origin`   | https://github.com/vpnhood/VpnHood.Core.Quic.MsQuic.AndroidNative.git |
| `upstream` | https://github.com/microsoft/msquic.git                  |
