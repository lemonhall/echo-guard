param(
  [string]$GodotDir = "E:\\Godot_v4.6-stable_win64.exe",
  [switch]$Console,
  [string]$OutDir = "",
  [int]$DelayMs = -1,
  [int]$DelayExtraMs = -1,
  [switch]$NoFrameAlign,
  [string[]]$UserArgs = @()
)

$ErrorActionPreference = "Stop"

$exe = if ($Console) {
  Join-Path $GodotDir "Godot_v4.6-stable_win64_console.exe"
} else {
  Join-Path $GodotDir "Godot_v4.6-stable_win64.exe"
}

if (-not (Test-Path $exe)) { throw "Godot executable not found: $exe" }
if (-not (Test-Path ".\\godot\\project.godot")) { throw "Missing Godot project: .\\godot\\project.godot" }

$engineArgs = @("--path", ".\\godot")

$user = @()
if ($OutDir -ne "") { $user += @("--eg-out-dir", $OutDir) }
if ($DelayMs -ge 0) { $user += @("--eg-delay-ms", "$DelayMs") }
if ($DelayExtraMs -ge 0) { $user += @("--eg-delay-extra-ms", "$DelayExtraMs") }
if ($NoFrameAlign) { $user += @("--eg-no-frame-align") }
if ($UserArgs.Count -gt 0) { $user += $UserArgs }

if ($user.Count -gt 0) {
  & $exe @engineArgs -- @user
} else {
  & $exe @engineArgs
}
