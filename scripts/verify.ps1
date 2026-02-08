param(
  [switch]$SkipNative,
  [switch]$SkipWsl,
  [switch]$UseUv,
  [switch]$RequireDeps
)

$ErrorActionPreference = "Stop"

function Write-Section([string]$title) {
  Write-Host ""
  Write-Host ("== {0} ==" -f $title)
}

function Require-Command([string]$name, [string]$help) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    Write-Host ("[FAIL] Missing command: {0}" -f $name)
    Write-Host ("       {0}" -f $help)
    return $false
  }
  Write-Host ("[ OK ] {0}: {1}" -f $name, $cmd.Source)
  return $true
}

$failures = 0

function Get-RepoRoot() {
  return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

Write-Section "Python Smoke Check"
$hasPython = Require-Command "python" "Install Python 3.12+ and ensure it's on PATH."
$hasUv = Require-Command "uv" "Install uv (https://astral.sh/uv) and ensure it's on PATH."

if ($hasPython) {
  $repoRoot = Get-RepoRoot
  Push-Location $repoRoot
  try {
    # Always run the smoke check without requiring any network/package install.
    & python .\python\src\echo_guard\verify.py
    if ($LASTEXITCODE -ne 0) { $failures++ }

    if ($UseUv) {
      if (-not $hasUv) {
        Write-Host "[FAIL] -UseUv set but uv missing"
        $failures++
      } else {
        $uvCache = Join-Path $repoRoot "build\\uv-cache"
        New-Item -ItemType Directory -Force -Path $uvCache | Out-Null
        $env:UV_CACHE_DIR = (Resolve-Path $uvCache).Path

        # Script mode avoids building/installing the local project (offline-friendly).
        & uv run --no-project -s .\python\src\echo_guard\verify.py
        if ($LASTEXITCODE -ne 0) { $failures++ }
      }
    } else {
      Write-Host "[ OK ] uv: (optional) run with -UseUv to validate uv execution path"
    }
  } finally {
    Pop-Location
  }
} else {
  $failures++
}

if (-not $SkipNative) {
  Write-Section "Native (C++) Toolchain Check"
  $hasCmake = Require-Command "cmake" "Install CMake (or run scripts/install_tools_windows.ps1 if you use winget)."

  if ($hasCmake) {
    $buildDir = Join-Path $PSScriptRoot "..\\build\\cpp"
    $buildDir = (Resolve-Path $buildDir -ErrorAction SilentlyContinue)?.Path ?? $buildDir
    cmake -S (Join-Path $PSScriptRoot "..\\cpp") -B $buildDir | Out-Host
    cmake --build $buildDir | Out-Host
    if ($LASTEXITCODE -ne 0) { $failures++ }
  } else {
    $failures++
  }
} else {
  Write-Section "Native (C++) Toolchain Check"
  Write-Host "[SKIP] -SkipNative set"
}

if (-not $SkipWsl) {
  Write-Section "WSL (webrtc-audio-processing) Check"
  $hasWsl = Require-Command "wsl" "Install WSL2 (Ubuntu 24 recommended) if you want to build webrtc-audio-processing."
  if ($hasWsl) {
    $webrtcPath = Join-Path $PSScriptRoot "..\\deps\\webrtc-audio-processing"
    $mesonFile = Join-Path $webrtcPath "meson.build"
    if (Test-Path $mesonFile) {
      Write-Host ("[ OK ] deps present: {0}" -f $webrtcPath)
    } else {
      Write-Host ("[WARN] deps missing or not initialized: {0}" -f $webrtcPath)
      Write-Host "       Fix: git submodule update --init --recursive"
      Write-Host "       See: deps/README.md and scripts/wsl/README.md"
      if ($RequireDeps) { $failures++ }
    }
  } else {
    $failures++
  }
} else {
  Write-Section "WSL (webrtc-audio-processing) Check"
  Write-Host "[SKIP] -SkipWsl set"
}

Write-Section "Deps (Submodule) Check"
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
  $repoRoot = Get-RepoRoot
  $gitmodules = Join-Path $repoRoot ".gitmodules"
  $subPath = Join-Path $repoRoot "deps\\webrtc-audio-processing"
  $mesonFile = Join-Path $subPath "meson.build"

  if (Test-Path $gitmodules) {
    Write-Host ("[ OK ] .gitmodules present: {0}" -f $gitmodules)
  } else {
    Write-Host "[WARN] .gitmodules not found (no submodules configured yet)"
    if ($RequireDeps) { $failures++ }
  }

  if (Test-Path $mesonFile) {
    Write-Host ("[ OK ] webrtc-audio-processing ready: {0}" -f $subPath)
  } else {
    Write-Host ("[WARN] webrtc-audio-processing not ready: {0}" -f $subPath)
    Write-Host "       Fix: git submodule update --init --recursive"
    if ($RequireDeps) { $failures++ }
  }
} else {
  Write-Host "[WARN] git not found; cannot validate submodules"
  if ($RequireDeps) { $failures++ }
}

Write-Host ""
if ($failures -eq 0) {
  Write-Host "[PASS] verify.ps1"
  exit 0
}

Write-Host ("[FAIL] verify.ps1 ({0} issue(s))" -f $failures)
exit 1
