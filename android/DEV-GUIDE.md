# Android Build — Developer Guide

Everything in this directory is VpnHood-specific and intentionally isolated so
upstream msquic merges stay conflict-free.

---

## Repository layout (VpnHood additions only)

```
android/
  build-android.ps1          # main build script (Windows PowerShell 7.2+)
  android-gcc-wrappers/      # generated at build time — do not commit
  artifacts/                 # generated at build time — do not commit
  DEV-GUIDE.md               # this file

submodules/
  CMakeLists.txt             # patched: wires OpenSSL into the msquic CMake build
  fix_openssl_makefile.cmake # post-generate hook: replaces \ with / in the
                             # OpenSSL Makefile so GNU make on Windows works

submodules/openssl/
  Configurations/15-android.conf  # patched (staged in submodule): normalises
                                  # NDK path to forward slashes inside OpenSSL's
                                  # Perl Configure so regex matching works on Windows
```

All other files are from upstream microsoft/msquic and should be left unmodified
unless a new upstream patch is needed.

---

## Prerequisites

| Tool | Notes |
|------|-------|
| PowerShell 7.2+ | `winget install Microsoft.PowerShell` |
| CMake ≥ 3.21 | Install to `C:\Program Files\CMake` — must appear in PATH **before** `C:\Strawberry\c\bin` (which ships an older cmake) |
| Ninja | Bundled with CMake or install separately |
| Android NDK r23+ | r28c tested; path **must not contain spaces** (see below) |
| Strawberry Perl | Required for OpenSSL's `Configure` script — Git's minimal Perl is insufficient |

### NDK path and spaces

OpenSSL's Perl `Configure` script uses the NDK path inside regex patterns.
Backslashes are regex metacharacters in Perl, and spaces break `cmake -E env`
quoting inside cmd.exe. For this reason the build script:

1. Resolves the NDK location.
2. Creates a junction `C:\AndroidNDK` → real NDK path (skipped if already exists).
3. Sets `ANDROID_NDK_ROOT` / `ANDROID_NDK_HOME` to the junction path with forward
   slashes.

**If your NDK is already at a space-free path** (e.g. `C:\Android\ndk\28.2.13676358`)
set `ANDROID_NDK_HOME` to it and the junction is still created but is a no-op
pass-through. Future work: make junction creation conditional on spaces being present.

---

## Building

```powershell
# from repo root — Release, both arches (default)
./android/build-android.ps1

# specific configuration / arch
./android/build-android.ps1 -Config Debug -Arch arm64
./android/build-android.ps1 -Config Release -Arch x64

# explicit NDK path (overrides auto-detect)
./android/build-android.ps1 -NdkPath "C:\AndroidNDK"

# wipe previous build tree before compiling (required when source root path changes)
./android/build-android.ps1 -Clean
```

### NDK auto-detection order (inside `Find-AndroidNdk`)

1. `-NdkPath` parameter
2. Environment variables: `ANDROID_NDK_LATEST_HOME`, `ANDROID_NDK_HOME`,
   `ANDROID_NDK_ROOT`, `ANDROID_NDK`
3. SDK Manager directories: `%LOCALAPPDATA%\Android\Sdk\ndk\*`,
   `C:\Android\Sdk\ndk\*`, `C:\android-sdk\ndk\*`

### Target architectures

Only two ABIs are built and shipped:

| Script `-Arch` | Android ABI | Notes |
|----------------|-------------|-------|
| `x64`          | `x86_64`    | Android emulator and x86-64 devices |
| `arm64`        | `arm64-v8a` | All modern Android phones/tablets |

32-bit ABIs (`x86`, `armeabi-v7a`) are intentionally excluded — VpnHood targets
API 29+ devices where 64-bit is universal.

### Outputs

```
android/artifacts/android/
  arm64_Release_openssl/libmsquic.so   ← arm64-v8a
  x64_Release_openssl/libmsquic.so    ← x86_64
```

Both directories are git-ignored and regenerated on every run.

---

## Consuming this from .NET (VpnHood QUIC on Android)

`VpnHood.Core.Quic.Android` drives MsQuic on Android via **P/Invoke over the C# bindings in
`src/cs/lib`** — it does **NOT** use `System.Net.Quic`. So a .NET consumer needs exactly two things
from this repo:

1. **`libmsquic.so`** (per ABI) — bundled into the APK. msquic statically links its own OpenSSL, so
   no `libcrypto`/`libssl` or .NET OpenSSL crypto shim is required.
2. **`src/cs/lib/msquic*.cs`** — the generated C# P/Invoke bindings, compiled into the consumer
   assembly. TLS certificate validation is done in managed code by the consumer using the **Android**
   crypto backend (`X509Certificate2` / `X509Chain`).

> **Do NOT** try to reuse `System.Net.Quic` on Android. It loads (`QuicConnection.IsSupported`
> becomes true with a bundled `libmsquic.so`) but **crashes in cert validation** (`X509_up_ref` on an
> Android cert handle passed to OpenSSL): its validation is hard-wired to the OpenSSL crypto backend,
> which clashes with Android's. Shipping `libcrypto`/`libssl`/the OpenSSL shim does not fix it. This
> was tried and abandoned — see `VpnHood/Src/Core/VpnHood.Core.Quic.Android/README.md` for the full
> rationale and the working client design (`AndroidQuicClient`/`Connection`/`Stream`,
> `DEFER_CERTIFICATE_VALIDATION`, SNI handling).

> Incremental-build note (consumer side): changing `libmsquic.so` is often **not** picked up by an
> incremental app build — rebuild the **app** project (`dotnet build -t:Rebuild`, or Clean+Rebuild in
> the IDE) and redeploy, otherwise the APK keeps the previously-gathered native libs.

---

## Key patches and why they exist

### `submodules/openssl/Configurations/15-android.conf`

**Problem:** OpenSSL's Perl `Configure` passes the NDK path to `which()` and then
matches the result against `$ndk` using a regex. On Windows, `which()` may return
8.3 short paths or backslash separators; `$ndk` uses forward slashes. The regex
never matches, so Configure reports "no NDK clang on $PATH" and aborts.

**Fix:** A `$which_f` helper is injected that:
- Calls `Win32::GetLongPathName` to expand 8.3 short paths.
- Replaces `\` with `/` in the returned path.

The NDK path stored in `$ndk` is also normalised to forward slashes early in
Configure via `$ndk =~ s|\\|/|g`.

This change is a **staged commit inside the openssl submodule**. To check its
status:
```bash
cd submodules/openssl && git status
```
To inspect the diff:
```bash
cd submodules/openssl && git diff --cached Configurations/15-android.conf
```
**Do not run `git submodule update --force`** — that would discard this patch.

### `submodules/fix_openssl_makefile.cmake`

**Problem:** OpenSSL's generated `Makefile` contains Windows backslash paths.
GNU make (from the NDK prebuilt) treats backslashes as line continuations or
escape characters, which corrupts the paths at compile time.

**Fix:** A CMake script invoked as a post-configure step replaces `\X` (where X
is a path character) with `/X` throughout the generated Makefile.

### `submodules/CMakeLists.txt`

Patched to wire the OpenSSL source tree (fetched via FetchContent pointing at
`submodules/openssl`) into the msquic build, and to invoke
`fix_openssl_makefile.cmake` after OpenSSL's configure step.

### `android/android-gcc-wrappers/`

Modern NDK (r18+) ships only API-level-suffixed clang binaries
(`aarch64-linux-android29-clang.cmd`) but OpenSSL's Configure looks for the
legacy GCC-triple names (`aarch64-linux-android-gcc`). The build script generates
thin `.cmd` shims here that forward calls to the correct clang binary. These are
regenerated every run and are git-ignored.

---

## Common errors and fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `CMakeCache.txt … different … source directory` | Stale build tree from a different repo location | Run with `-Clean` |
| `no NDK clang on $PATH` | `15-android.conf` patch missing or NDK path mismatch | Verify patch is staged: `cd submodules/openssl && git status` |
| `cmake not found` / old cmake picked up | Strawberry Perl puts an old cmake in `C:\Strawberry\c\bin` | Ensure `C:\Program Files\CMake\bin` comes first in PATH (script does this automatically) |
| OpenSSL Makefile build fails with path errors | `fix_openssl_makefile.cmake` not applied | Check `submodules/CMakeLists.txt` still calls it post-configure |
| NDK not found | No env var set, NDK under `Program Files` path not in search list | Pass `-NdkPath` explicitly or set `ANDROID_NDK_HOME` |

---

## Updating from upstream msquic

```bash
git fetch upstream
git merge upstream/main          # or a release tag, e.g. upstream/v2.6.0
git submodule update --init --recursive
```

Conflicts can only occur on the files listed in the "Key patches" section above
(`CMakeLists.txt`, `submodules/CMakeLists.txt`, `submodules/fix_openssl_makefile.cmake`).
The `android/` directory is never touched by upstream. After resolving any conflicts,
verify the openssl submodule patch is still intact, then rebuild with `-Clean`.

---

## Updating the OpenSSL submodule

```bash
cd submodules/openssl
git fetch
git checkout <new-tag>           # e.g. openssl-3.6.0
cd ../..
git add submodules/openssl
```

After bumping, re-apply (or verify) the `15-android.conf` patch, run with `-Clean`,
and confirm the build succeeds before committing.
