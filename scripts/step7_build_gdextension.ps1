param(
  [string]$GodotDir = "E:\\Godot_v4.6-stable_win64.exe",
  [string]$GodotExe = "",
  [ValidateSet("2019","2022")]
  [string]$PreferVs = "2019",
  [switch]$DebugOnly,
  [switch]$ReleaseOnly
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "win\\vs.ps1")

function Get-GodotConsoleExe() {
  if ($GodotExe -ne "") { return $GodotExe }
  $p = Join-Path $GodotDir "Godot_v4.6-stable_win64_console.exe"
  if (Test-Path $p) { return $p }
  $p = Join-Path $GodotDir "Godot_v4.6-stable_win64.exe"
  if (Test-Path $p) { return $p }
  throw "Godot executable not found. Provide -GodotExe or -GodotDir. Tried: $p"
}

function Ensure-Scons() {
  & scons --version | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "SCons not available. Install with: pwsh -File scripts/install_tools_windows.ps1 -InstallScons"
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$godot = Get-GodotConsoleExe

if (-not (Test-Path (Join-Path $repoRoot "deps\\godot-cpp\\SConstruct"))) {
  throw "Missing deps/godot-cpp. Init submodules: git submodule update --init --recursive"
}
if (-not (Test-Path (Join-Path $repoRoot "godot\\native\\echo_guard\\SConstruct"))) {
  throw "Missing native extension project: godot/native/echo_guard"
}

Ensure-Scons

$apiDir = Join-Path $repoRoot "build\\godot_api"
New-Item -ItemType Directory -Force -Path $apiDir | Out-Null

Push-Location $apiDir
try {
  Write-Host "[INFO] Dumping extension_api.json via Godot..."
  & $godot --dump-extension-api | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "Godot --dump-extension-api failed (exit=$LASTEXITCODE)" }
} finally {
  Pop-Location
}

$apiFile = Join-Path $apiDir "extension_api.json"
if (-not (Test-Path $apiFile)) { throw "Expected extension_api.json not found: $apiFile" }

$nativeDir = Join-Path $repoRoot "godot\\native\\echo_guard"

$buildDebug = -not $ReleaseOnly
$buildRelease = -not $DebugOnly
if (-not $buildDebug -and -not $buildRelease) { throw "Pick at least one: -DebugOnly or -ReleaseOnly (or neither for both)." }

if ($buildDebug) {
  Write-Host ""
  Write-Host "[INFO] Building GDExtension (template_debug)..."
  $code = Invoke-InVsDevCmd -Prefer $PreferVs -Command ("cd /d ""{0}"" && scons platform=windows target=template_debug arch=x86_64 generate_bindings=yes custom_api_file=""{1}""" -f $nativeDir, $apiFile)
  if ($code -ne 0) { throw "Build failed (template_debug), exit=$code" }
}

if ($buildRelease) {
  Write-Host ""
  Write-Host "[INFO] Building GDExtension (template_release)..."
  $code = Invoke-InVsDevCmd -Prefer $PreferVs -Command ("cd /d ""{0}"" && scons platform=windows target=template_release arch=x86_64 generate_bindings=yes custom_api_file=""{1}""" -f $nativeDir, $apiFile)
  if ($code -ne 0) { throw "Build failed (template_release), exit=$code" }
}

Write-Host ""
Write-Host "[OK] Built extension libs under: $repoRoot\\godot\\bin"
