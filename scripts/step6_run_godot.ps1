param(
  [string]$GodotDir = "E:\\Godot_v4.6-stable_win64.exe",
  [switch]$Console,
  [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"

$exe = if ($Console) {
  Join-Path $GodotDir "Godot_v4.6-stable_win64_console.exe"
} else {
  Join-Path $GodotDir "Godot_v4.6-stable_win64.exe"
}

if (-not (Test-Path $exe)) { throw "Godot executable not found: $exe" }
if (-not (Test-Path ".\\godot\\project.godot")) { throw "Missing Godot project: .\\godot\\project.godot" }

if ($OutDir -ne "") {
  & $exe --path .\\godot -- --eg-out-dir $OutDir
} else {
  & $exe --path .\\godot
}
