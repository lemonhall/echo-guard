param(
  [string]$GodotDir = "E:\\Godot_v4.6-stable_win64.exe",
  [string]$GodotExe = "",
  [ValidateSet("2019","2022")]
  [string]$PreferVs = "2019",
  [switch]$ForceApiDump
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

function Require-Tool([string]$name, [string]$installHint) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "Missing tool: $name. $installHint" }
}

Require-Tool "scons" "Install with: python -m pip install --user -U scons"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$godot = Get-GodotConsoleExe

if (-not (Test-Path (Join-Path $repoRoot "deps\\godot-cpp\\SConstruct"))) {
  throw "Missing deps/godot-cpp. Run: git submodule update --init --recursive"
}
if (-not (Test-Path (Join-Path $repoRoot "godot\\native\\echo_guard\\SConstruct"))) {
  throw "Missing native extension project: godot/native/echo_guard"
}

$apiDir = Join-Path $repoRoot "build\\godot_api"
New-Item -ItemType Directory -Force -Path $apiDir | Out-Null
$apiFile = Join-Path $apiDir "extension_api.json"

if (-not (Test-Path $apiFile) -or $ForceApiDump) {
  Push-Location $apiDir
  try {
    Write-Host "[INFO] Dumping extension_api.json via Godot..."
    & $godot --dump-extension-api | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Godot --dump-extension-api failed (exit=$LASTEXITCODE)" }
  } finally {
    Pop-Location
  }
} else {
  Write-Host "[INFO] extension_api.json exists; skipping dump."
}

if (-not (Test-Path $apiFile)) { throw "Expected extension_api.json not found: $apiFile" }

$nativeDir = Join-Path $repoRoot "godot\\native\\echo_guard"

Write-Host ""
Write-Host "[INFO] Initial build (slow, one-time): generate_bindings=yes (debug + release)"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
  $code = Invoke-InVsDevCmd -Prefer $PreferVs -Command ("cd /d ""{0}"" && scons platform=windows target=template_debug arch=x86_64 generate_bindings=yes custom_api_file=""{1}""" -f $nativeDir, $apiFile)
  if ($code -ne 0) { throw "Build failed (template_debug), exit=$code" }

  $code = Invoke-InVsDevCmd -Prefer $PreferVs -Command ("cd /d ""{0}"" && scons platform=windows target=template_release arch=x86_64 generate_bindings=yes custom_api_file=""{1}""" -f $nativeDir, $apiFile)
  if ($code -ne 0) { throw "Build failed (template_release), exit=$code" }
} finally {
  $sw.Stop()
}

Write-Host ""
Write-Host ("[OK] Init complete in {0:n1}s" -f $sw.Elapsed.TotalSeconds)
Write-Host ("[OK] extension_api.json: {0}" -f $apiFile)
Write-Host ("[OK] DLLs: {0}" -f (Join-Path $repoRoot "godot\\bin"))

