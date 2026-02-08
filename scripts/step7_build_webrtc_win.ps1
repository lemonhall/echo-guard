param(
  [ValidateSet("2019","2022")]
  [string]$PreferVs = "2019",
  [ValidateSet("debug","release")]
  [string]$Config = "release",
  [switch]$Reconfigure
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "win\\vs.ps1")

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$webrtcDir = Join-Path $repoRoot "deps\\webrtc-audio-processing"
if (-not (Test-Path (Join-Path $webrtcDir "meson.build"))) {
  throw "Missing deps/webrtc-audio-processing. Init submodules: git submodule update --init --recursive"
}

if (-not (Get-Command meson -ErrorAction SilentlyContinue)) {
  throw "meson not found. Install: pwsh -File scripts/install_tools_windows.ps1 -InstallMeson"
}
if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
  throw "ninja not found. Install: pwsh -File scripts/install_tools_windows.ps1 -InstallNinja"
}

$buildDir = Join-Path $webrtcDir "build-win"
$installDir = Join-Path $webrtcDir "install-win"

$buildType = if ($Config -eq "debug") { "debug" } else { "release" }

$setupArgs = @(
  "meson", "setup",
  """$buildDir""",
  "--buildtype=$buildType",
  "--backend=ninja",
  "--default-library=static",
  "-Db_vscrt=mt",
  "--prefix", """$installDir"""
)
if ($Reconfigure) { $setupArgs += "--reconfigure" }

Write-Host "[INFO] webrtc-audio-processing (Windows/MSVC)"
Write-Host "[INFO] build:   $buildDir"
Write-Host "[INFO] install: $installDir"

$setupCmd = ($setupArgs -join " ")
$code = Invoke-InVsDevCmd -Prefer $PreferVs -Command ("cd /d ""{0}"" && {1}" -f $webrtcDir, $setupCmd)
if ($code -ne 0) { throw "meson setup failed (exit=$code)" }

$code = Invoke-InVsDevCmd -Prefer $PreferVs -Command ("cd /d ""{0}"" && meson compile -C ""{1}""" -f $webrtcDir, $buildDir)
if ($code -ne 0) { throw "meson compile failed (exit=$code)" }

$code = Invoke-InVsDevCmd -Prefer $PreferVs -Command ("cd /d ""{0}"" && meson install -C ""{1}""" -f $webrtcDir, $buildDir)
if ($code -ne 0) { throw "meson install failed (exit=$code)" }

Write-Host ""
Write-Host "[OK] Installed under: $installDir"
