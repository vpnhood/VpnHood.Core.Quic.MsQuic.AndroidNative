#Requires -Version 7.2
<#
.SYNOPSIS
    Copies the upstream msquic C# binding files into the VpnHood project's
    Bindings/ folder, replacing all 'internal' access modifiers with 'public'.

.DESCRIPTION
    Run this after pulling a new msquic upstream that regenerates src/cs/lib/*.cs.
    The output files are committed — no build-time transformation needed.

.EXAMPLE
    .\scripts\publicize-bindings.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$src = Join-Path $repoRoot "src\cs\lib"
$dst = Join-Path $repoRoot "android\AndroidNative\Bindings"

$files = @(
    "msquic.cs",
    "msquic_generated.cs",
    "msquic_generated_windows.cs",
    "msquic_generated_linux.cs",
    "msquic_generated_macos.cs",
    "msquic_extensions.cs",
    "MsQuicException.cs"
)

New-Item -ItemType Directory -Force -Path $dst | Out-Null

foreach ($f in $files) {
    $content = [System.IO.File]::ReadAllText("$src\$f")
    $patched = [System.Text.RegularExpressions.Regex]::Replace($content, '\binternal\b', 'public')
    [System.IO.File]::WriteAllText("$dst\$f", $patched)
    $n = ([System.Text.RegularExpressions.Regex]::Matches($content, '\binternal\b')).Count
    Write-Host "  $f  ($n substitution(s))"
}

Write-Host ""
Write-Host "Done. Commit the updated Bindings\ files."
