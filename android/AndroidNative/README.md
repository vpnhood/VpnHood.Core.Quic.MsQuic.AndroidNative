# VpnHood.Core.Quic.MsQuic.AndroidNative

A **self-contained native QUIC package for Android**. It ships:

1. The prebuilt **`libmsquic.so`** per ABI (`arm64-v8a`, `x86_64`), **committed** under `native/` so the
   binary travels with the package — consumers never build or link it.
2. The **`Microsoft.Quic` C# P/Invoke bindings** — a committed, self-contained copy under `Bindings/` with
   **public** types, picked up by the SDK's default `.cs` globbing.

It has **no VpnHood dependencies** (no abstractions, no NuGet references). Its whole job is to hide the
native-linking complexity behind one reference.

## Consuming it

`VpnHood.Core.Quic.Android` references this project (locally today, the published NuGet
`VpnHood.Core.Quic.MsQuic.AndroidNative` later) and gets both the bundled `.so` (flows transitively into
the APK as `lib/<abi>/libmsquic.so`) and the bindings. Because the binding types are **public**, consumers
use them directly — no `InternalsVisibleTo` needed (which also makes the package usable by any consumer
once published, not just one named assembly).

## Updating the native binary

The `.so` is produced by this repo's `android/build-android.ps1` (see `android/DEV-GUIDE.md`), which writes
to the git-ignored `android/artifacts/`. On build, the `RefreshMsQuicNative` MSBuild target copies the
freshly built `.so` into the committed `native/` folder; commit the change to publish a new binary. On a
clean checkout with no `artifacts/`, the committed `native/` copy is used as-is.

Only `arm64-v8a` and `x86_64` are produced; 32-bit ABIs are intentionally excluded.
