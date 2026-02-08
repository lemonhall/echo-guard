param(
  [string]$GodotDir = "E:\\Godot_v4.6-stable_win64.exe"
)

$ErrorActionPreference = "Stop"

$exe = Join-Path $GodotDir "Godot_v4.6-stable_win64_console.exe"
if (-not (Test-Path $exe)) { throw "Godot console executable not found: $exe" }

& $exe --headless --quit --path .\\godot -- --eg-no-mic
if ($LASTEXITCODE -ne 0) { throw "Godot headless smoke failed: $LASTEXITCODE" }

Write-Host "[OK] Godot headless smoke passed"
