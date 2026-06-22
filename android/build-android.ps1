#Requires -Version 7.2
<#
.SYNOPSIS
    Builds msquic for Android x64 (x86_64) and arm64 (arm64-v8a) on Windows.

.DESCRIPTION
    Locates the Android NDK, then runs CMake to cross-compile msquic for
    Android API 29+ using OpenSSL as the TLS backend.

.PARAMETER Config
    Build configuration: Debug or Release (default: Release)

.PARAMETER Arch
    Target architecture: x64, arm64, or both (default: both)

.PARAMETER ApiLevel
    Android API level (default: 29)

.PARAMETER NdkPath
    Explicit path to the Android NDK root. If omitted the script searches
    common locations and environment variables.

.PARAMETER Clean
    Delete previous build and artifact directories before building.

.EXAMPLE
    .\build-android.ps1
    .\build-android.ps1 -Config Debug -Arch arm64
    .\build-android.ps1 -NdkPath "C:\Android\Sdk\ndk\27.2.12479018"
#>
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Debug", "Release")]
    [string]$Config = "Release",

    [Parameter(Mandatory = $false)]
    [ValidateSet("x64", "arm64", "both")]
    [string]$Arch = "both",

    [Parameter(Mandatory = $false)]
    [int]$ApiLevel = 29,

    [Parameter(Mandatory = $false)]
    [string]$NdkPath = "",

    [Parameter(Mandatory = $false)]
    [switch]$Clean = $false
)

Set-StrictMode -Version 'Latest'
$ErrorActionPreference = 'Stop'

# This script lives in <msquic>/android, so the msquic source root is its parent.
$RepoDir = Split-Path $PSScriptRoot -Parent

# ---------------------------------------------------------------------------
# Locate the Android NDK
# ---------------------------------------------------------------------------
function Find-AndroidNdk {
    # 1. Explicit parameter
    if ($NdkPath -ne "" -and (Test-Path $NdkPath)) {
        return $NdkPath
    }

    # 2. Environment variables (CI / user-set)
    foreach ($envVar in @("ANDROID_NDK_LATEST_HOME", "ANDROID_NDK_HOME", "ANDROID_NDK_ROOT", "ANDROID_NDK")) {
        $val = [System.Environment]::GetEnvironmentVariable($envVar)
        if ($val -and (Test-Path $val)) {
            Write-Host "Found NDK via `$$envVar`: $val"
            return $val
        }
    }

    # 3. Android Studio / SDK Manager default locations
    $sdkRoots = @(
        "$env:LOCALAPPDATA\Android\Sdk",
        "$env:USERPROFILE\AppData\Local\Android\Sdk",
        "C:\Android\Sdk",
        "C:\android-sdk"
    )
    foreach ($sdk in $sdkRoots) {
        $ndkDir = Join-Path $sdk "ndk"
        if (Test-Path $ndkDir) {
            # Pick the newest installed NDK version
            $latest = Get-ChildItem $ndkDir -Directory |
                        Sort-Object Name -Descending |
                        Select-Object -First 1
            if ($latest) {
                Write-Host "Found NDK in SDK manager: $($latest.FullName)"
                return $latest.FullName
            }
        }
    }

    return $null
}

# ---------------------------------------------------------------------------
# Build one architecture
# ---------------------------------------------------------------------------
function Build-Android {
    param(
        [string]$TargetArch,   # "x64" or "arm64"
        [string]$Ndk
    )

    # Map our arch names to Android ABI names
    $androidAbi = switch ($TargetArch) {
        "x64"   { "x86_64" }
        "arm64" { "arm64-v8a" }
    }

    $buildDir     = Join-Path $RepoDir "build\android\${TargetArch}_openssl"
    $artifactsDir = Join-Path $PSScriptRoot "artifacts\android\${TargetArch}_${Config}_openssl"

    if ($Clean) {
        if (Test-Path $buildDir)     { Remove-Item $buildDir     -Recurse -Force }
        if (Test-Path $artifactsDir) { Remove-Item $artifactsDir -Recurse -Force }
    }

    New-Item -Path $buildDir     -ItemType Directory -Force | Out-Null
    New-Item -Path $artifactsDir -ItemType Directory -Force | Out-Null

    # Create a junction at a space-free path — spaces in the NDK path break both
    # cmd.exe quoting inside cmake -E env AND OpenSSL's Perl regex parser.
    $ndkJunction = "C:\AndroidNDK"
    if (-not (Test-Path $ndkJunction)) {
        cmd /c mklink /J "$ndkJunction" "$Ndk" | Out-Null
        Write-Host "Created NDK junction: $ndkJunction -> $Ndk"
    }
    $Ndk = $ndkJunction

    # Set ANDROID_NDK_ROOT with forward slashes — OpenSSL's Perl code uses it in
    # regex patterns; backslashes are regex metacharacters in Perl.
    $ndkFwd = $Ndk.Replace('\', '/')
    $env:ANDROID_NDK_ROOT = $ndkFwd
    $env:ANDROID_NDK_HOME = $ndkFwd
    Write-Host "ANDROID_NDK_ROOT: $ndkFwd"

    $toolchainFile = Join-Path $Ndk "build\cmake\android.toolchain.cmake"
    if (-not (Test-Path $toolchainFile)) {
        throw "NDK toolchain file not found: $toolchainFile"
    }

    # Force system cmake to front of PATH — Strawberry Perl installs cmake.exe in
    # c\bin which may appear earlier in PATH and would shadow system cmake 4.x.
    $systemCmake = "C:\Program Files\CMake\bin"
    if (Test-Path $systemCmake) {
        $env:PATH = "$systemCmake;$env:PATH"
    }

    # Clear SHELL — if set to sh.exe (e.g. from a prior run), GNU make would use it
    # and mangle Windows backslash paths. cmd.exe is correct for our Makefile.
    Remove-Item Env:\SHELL -ErrorAction SilentlyContinue

    # Add Git usr/bin to PATH (provides rm, cp, mkdir etc. used in OpenSSL Makefile)
    # WITHOUT setting SHELL — GNU make will use cmd.exe so Windows backslash paths
    # in Perl commands are handled correctly, while rm/cp resolve via PATH.
    $gitUsrBin = "C:\Program Files\Git\usr\bin"
    $shJunction = "C:\GitSh"
    if ((Test-Path $gitUsrBin) -and (-not (Test-Path $shJunction))) {
        cmd /c mklink /J "$shJunction" "$gitUsrBin" | Out-Null
    }
    if (Test-Path $shJunction) {
        $env:PATH = "$shJunction;$env:PATH"
    }

    # Add NDK clang toolchain to PATH (Windows prebuilt)
    $ndkClangBin = Join-Path $Ndk "toolchains\llvm\prebuilt\windows-x86_64\bin"
    if (Test-Path $ndkClangBin) {
        $env:PATH = "$ndkClangBin;$env:PATH"
    }

    # Add NDK prebuilt bin to PATH — contains make.exe needed by OpenSSL build
    $ndkPrebuiltBin = Join-Path $Ndk "prebuilt\windows-x86_64\bin"
    if (Test-Path $ndkPrebuiltBin) {
        $env:PATH = "$ndkPrebuiltBin;$env:PATH"
    }

    # Prefer Strawberry Perl (full CPAN, required by OpenSSL Configure) over Git's minimal Perl
    # Only add perl\bin — NOT c\bin (which contains a bundled cmake that would shadow the system cmake)
    $strawberryPerl = "C:\Strawberry\perl\bin"
    if (Test-Path $strawberryPerl) {
        $env:PATH = "$strawberryPerl;$env:PATH"
        Write-Host "Using Strawberry Perl: $strawberryPerl"
    } else {
        # Fallback: Git's usr\bin — has perl.exe but minimal modules
        $gitPerlBin = "C:\Program Files\Git\usr\bin"
        if (Test-Path $gitPerlBin) {
            $env:PATH = "$gitPerlBin;$env:PATH"
            Write-Host "Using Git Perl (fallback): $gitPerlBin"
        }
    }

    # OpenSSL's Configure looks for "<triple>-gcc" / "<triple>-ar" / "<triple>-ranlib"
    # but modern NDK (r18+) only ships clang-based compilers with API-level suffixes.
    # Create a temporary directory with wrapper .cmd scripts that forward to the
    # appropriate API-versioned clang binaries so OpenSSL Configure can find them.
    $wrapperDir = Join-Path $PSScriptRoot "android-gcc-wrappers"
    New-Item -ItemType Directory -Force -Path $wrapperDir | Out-Null
    $clangBin = Join-Path $Ndk "toolchains\llvm\prebuilt\windows-x86_64\bin"

    $tripleMap = @{
        "x86_64"  = "x86_64-linux-android"
        "arm64-v8a" = "aarch64-linux-android"
    }
    foreach ($triple in $tripleMap.Values) {
        $clangExe    = Join-Path $clangBin "${triple}${ApiLevel}-clang.cmd"
        $clangPPExe  = Join-Path $clangBin "${triple}${ApiLevel}-clang++.cmd"
        $llvmBin     = Join-Path $clangBin "llvm-ar.exe"
        $llvmRanlib  = Join-Path $clangBin "llvm-ranlib.exe"
        $llvmStrip   = Join-Path $clangBin "llvm-strip.exe"

        "@echo off`n`"$clangExe`" %*"   | Set-Content "$wrapperDir\${triple}-gcc.cmd"    -Encoding ASCII
        "@echo off`n`"$clangPPExe`" %*" | Set-Content "$wrapperDir\${triple}-g++.cmd"    -Encoding ASCII
        "@echo off`n`"$llvmBin`" %*"    | Set-Content "$wrapperDir\${triple}-ar.cmd"     -Encoding ASCII
        "@echo off`n`"$llvmRanlib`" %*" | Set-Content "$wrapperDir\${triple}-ranlib.cmd" -Encoding ASCII
        "@echo off`n`"$llvmStrip`" %*"  | Set-Content "$wrapperDir\${triple}-strip.cmd"  -Encoding ASCII
    }
    $env:PATH = "$wrapperDir;$env:PATH"
    Write-Host "Android GCC wrappers created in: $wrapperDir"

    # CMake configure
    # Note: when using PowerShell's & operator with @array, PowerShell handles
    # quoting of paths with spaces automatically — do NOT add embedded quotes.
    $cmakeBuildType = if ($Config -eq "Release") { "RelWithDebInfo" } else { "Debug" }

    $cmakeArgs = @(
        "-G", "Ninja",
        "-DCMAKE_TOOLCHAIN_FILE=$toolchainFile",
        "-DANDROID_ABI=$androidAbi",
        "-DANDROID_PLATFORM=android-$ApiLevel",
        "-DANDROID_NDK=$Ndk",
        "-DQUIC_TLS_LIB=openssl",
        "-DQUIC_OUTPUT_DIR=$artifactsDir",
        "-DQUIC_ENABLE_LOGGING=off",
        "-DQUIC_BUILD_TOOLS=off",
        "-DQUIC_BUILD_TEST=off",
        "-DQUIC_BUILD_PERF=off",
        "-DQUIC_SKIP_CI_CHECKS=ON",
        "-DQUIC_LIBRARY_NAME=msquic",
        "-DCMAKE_BUILD_TYPE=$cmakeBuildType",
        $RepoDir
    )

    Write-Host ""
    Write-Host "=== Configuring for Android $androidAbi (API $ApiLevel, $Config) ==="
    Write-Host "Build dir:     $buildDir"
    Write-Host "Artifacts dir: $artifactsDir"
    Write-Host ""

    Push-Location $buildDir
    try {
        & cmake @cmakeArgs
        if ($LASTEXITCODE -ne 0) { throw "CMake configure failed for $androidAbi" }

        Write-Host ""
        Write-Host "=== Building for Android $androidAbi ==="
        & cmake --build . --parallel
        if ($LASTEXITCODE -ne 0) { throw "CMake build failed for $androidAbi" }
    } finally {
        Pop-Location
    }

    Write-Host ""
    Write-Host "=== Artifacts for $androidAbi ==="
    Get-ChildItem $artifactsDir -Recurse -File | ForEach-Object { Write-Host "  $($_.FullName)" }
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

# Check for CMake
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw "cmake not found in PATH. Install CMake >= 3.21 and add it to PATH."
}
$cmakeVersion = (cmake --version | Select-Object -First 1)
Write-Host "CMake: $cmakeVersion"

# Check for Ninja
if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    # Try to find it bundled with CMake or Android SDK
    $ninjaLocations = @(
        (Join-Path (Split-Path (Get-Command cmake).Source -Parent) "ninja.exe"),
        "$env:LOCALAPPDATA\Android\Sdk\cmake\*\bin\ninja.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($ninjaLocations) {
        $env:PATH = "$(Split-Path $ninjaLocations -Parent);$env:PATH"
        Write-Host "Found ninja at: $ninjaLocations"
    } else {
        throw "ninja not found. Install Ninja and add it to PATH, or install via Android Studio SDK manager (cmake package includes ninja)."
    }
} else {
    Write-Host "Ninja: $(ninja --version)"
}

# Verify msquic was cloned
if (-not (Test-Path (Join-Path $RepoDir "CMakeLists.txt"))) {
    throw "msquic source not found at '$RepoDir'. Submodules may be missing — run: git submodule update --init --recursive"
}

# Locate NDK
$ndk = Find-AndroidNdk
if (-not $ndk) {
    throw @"
Android NDK not found. Please do one of the following:
  1. Set the ANDROID_NDK_HOME (or ANDROID_NDK_ROOT) environment variable to the NDK root.
  2. Install the NDK via Android Studio: SDK Manager → SDK Tools → NDK (Side by side).
  3. Pass -NdkPath 'C:\path\to\ndk' to this script.
"@
}
Write-Host "Using NDK: $ndk"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
$archsToBuild = switch ($Arch) {
    "x64"   { @("x64") }
    "arm64" { @("arm64") }
    "both"  { @("x64", "arm64") }
}

foreach ($a in $archsToBuild) {
    Build-Android -TargetArch $a -Ndk $ndk
}

Write-Host ""
Write-Host "=== All builds completed successfully ==="
Write-Host "Artifacts are in: $(Join-Path $PSScriptRoot 'artifacts\android')"
