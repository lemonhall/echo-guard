param(
  [string]$GodotDir = "E:\\Godot_v4.6-stable_win64.exe",
  [switch]$Console,
  [ValidateSet("2019","2022")]
  [string]$PreferVs = "2019"
)

$ErrorActionPreference = "Stop"

function Ensure-Command([string]$name, [scriptblock]$install) {
  if (Get-Command $name -ErrorAction SilentlyContinue) { return }
  & $install
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Missing required tool: $name"
  }
}

function Get-WeRtcInstallWinVersion([string]$webrtcDir) {
  $pcDir = Join-Path $webrtcDir "install-win\\lib\\pkgconfig"
  $pcs = @(
    (Join-Path $pcDir "webrtc-audio-processing-2.pc"),
    (Join-Path $pcDir "webrtc-audio-processing.pc")
  ) | Where-Object { Test-Path $_ }
  $pc = $pcs | Select-Object -First 1
  if (-not $pc) { return $null }
  $line = Get-Content -ErrorAction SilentlyContinue $pc | Where-Object { $_ -match "^Version\\s*:" } | Select-Object -First 1
  if (-not $line) { return $null }
  return ($line -replace "^Version\\s*:\\s*", "").Trim()
}

function Find-WeRtcInstallWinLib([string]$webrtcDir) {
  $libDir = Join-Path $webrtcDir "install-win\\lib"
  if (-not (Test-Path $libDir)) { return $null }

  $preferred = @(
    (Join-Path $libDir "libwebrtc-audio-processing-2.a"),
    (Join-Path $libDir "libwebrtc_audio_processing.a"),
    (Join-Path $libDir "webrtc-audio-processing-2.lib"),
    (Join-Path $libDir "webrtc_audio_processing.lib")
  )

  foreach ($p in $preferred) {
    if (Test-Path $p) { return $p }
  }

  $fallback = Get-ChildItem -File -ErrorAction SilentlyContinue $libDir -Include "*.a","*.lib" |
    Where-Object { $_.Name -match "webrtc" -and $_.Name -match "audio" -and $_.Name -match "processing" } |
    Select-Object -First 1 -ExpandProperty FullName
  return $fallback
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $repoRoot
try {
  # 1) Ensure submodules are present (godot-cpp + webrtc-audio-processing sources).
  if (-not (Test-Path ".\\deps\\godot-cpp\\SConstruct") -or -not (Test-Path ".\\deps\\webrtc-audio-processing\\meson.build")) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git not found on PATH" }
    git submodule update --init --recursive | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "git submodule update failed" }
  }

  # 2) Ensure Python + pip.
  if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw "python not found on PATH" }
  python -m pip --version | Out-Host

  # 3) Ensure build tools (pip --user).
  Ensure-Command "scons" { python -m pip install --user --upgrade scons | Out-Host }
  Ensure-Command "meson" { python -m pip install --user --upgrade meson | Out-Host }
  Ensure-Command "ninja" { python -m pip install --user --upgrade ninja | Out-Host }

  # 4) Ensure MSVC callable (prints toolchain paths).
  pwsh -NoProfile -File .\\scripts\\step7_probe_msvc.ps1 -Prefer $PreferVs | Out-Host

  # 5) Build WebRTC APM for Windows (one-time, cached under deps/.../install-win).
  $webrtcDir = Join-Path $repoRoot "deps\\webrtc-audio-processing"
  $webrtcLib = Find-WeRtcInstallWinLib $webrtcDir
  $webrtcVer = Get-WeRtcInstallWinVersion $webrtcDir
  $needWeRtcBuild = (-not $webrtcLib) -or (-not $webrtcVer) -or ($webrtcVer -notmatch '^2\\.1(\\.|$)')
  if ($needWeRtcBuild) {
    if (-not $webrtcVer) {
      Write-Host "[INFO] Building webrtc-audio-processing for Windows (install-win version unknown)..."
    } else {
      Write-Host ("[INFO] Building webrtc-audio-processing for Windows (install-win version={0} != 2.1)..." -f $webrtcVer)
    }
    pwsh -NoProfile -File .\\scripts\\step7_build_webrtc_win.ps1 -PreferVs $PreferVs -Reconfigure | Out-Host
    $webrtcLib = Find-WeRtcInstallWinLib $webrtcDir
    if (-not $webrtcLib) { throw "webrtc-audio-processing build did not produce a library under: $webrtcDir\\install-win\\lib" }
    $webrtcVer = Get-WeRtcInstallWinVersion $webrtcDir
  }

  # 6) Build GDExtension DLL (one-time, output under godot/bin).
  if (-not (Test-Path ".\\godot\\bin\\libecho_guard.windows.template_debug.x86_64.dll")) {
    pwsh -NoProfile -File .\\scripts\\step7_build_gdextension.ps1 -PreferVs $PreferVs -GodotDir $GodotDir -DebugOnly | Out-Host
  }

  # 7) Launch Godot project.
  $args = @("-NoProfile", "-File", ".\\scripts\\step6_run_godot.ps1", "-GodotDir", $GodotDir)
  if ($Console) { $args += "-Console" }
  pwsh @args
} finally {
  Pop-Location
}

