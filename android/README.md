# VpnHood — msquic for Android (native)

This is a **fork of [microsoft/msquic](https://github.com/microsoft/msquic)** kept by VpnHood
to cross-compile msquic for Android (x86_64 and arm64-v8a) on Windows, using OpenSSL as the
TLS backend.

Everything VpnHood-specific lives under this `android/` directory so that merges from the
upstream msquic repository stay conflict-free. The only changes outside this folder are the
minimal source patches required for the Android/OpenSSL-on-Windows build (e.g. `CMakeLists.txt`
and `submodules/fix_openssl_makefile.cmake`).

## Building

Requirements: Windows + PowerShell 7.2+, CMake ≥ 3.21, Ninja, the Android NDK, and
Strawberry Perl (for OpenSSL's `Configure`).

```powershell
# from the repo root
./android/build-android.ps1                       # Release, both arches
./android/build-android.ps1 -Config Debug -Arch arm64
./android/build-android.ps1 -NdkPath "C:\Android\Sdk\ndk\27.2.12479018"
```

Outputs (all git-ignored, regenerated each run):
- `android/artifacts/android/<arch>_<config>_openssl/` — the built `libmsquic.so`
- `android/android-gcc-wrappers/` — generated NDK toolchain shims
- `build/android/<arch>_openssl/` — CMake/Ninja build tree

## Updating from upstream msquic

`origin` is this VpnHood fork; `upstream` is microsoft/msquic.

```bash
git fetch upstream
git merge upstream/main          # or pin to a release tag, e.g. upstream/v2.6.0
git submodule update --init --recursive
```

Conflicts can only occur on the few upstream files we patched (e.g. `CMakeLists.txt`);
the `android/` tooling is never touched by upstream. Resolve, rebuild, and push.

## Fresh clone

```bash
git clone --recurse-submodules https://github.com/vpnhood/VpnHood.Core.Quic.MsQuic.AndroidNative.git
```

## Remotes

| name       | url                                                      |
|------------|----------------------------------------------------------|
| `origin`   | https://github.com/vpnhood/VpnHood.Core.Quic.MsQuic.AndroidNative.git |
| `upstream` | https://github.com/microsoft/msquic.git                  |
