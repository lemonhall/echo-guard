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
  if (-not (Test-Path ".\\deps\\webrtc-audio-processing\\install-win\\lib\\libwebrtc_audio_processing.a")) {
    pwsh -NoProfile -File .\\scripts\\step7_build_webrtc_win.ps1 -PreferVs $PreferVs -Reconfigure | Out-Host
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

