param(
  [string]$CaptureDir = "",
  [int]$DelayMs = 0,
  [ValidateRange(0, 3)]
  [int]$Aggressiveness = 2
)

$ErrorActionPreference = "Stop"

function To-WslPath([string]$path) {
  $p = (Resolve-Path $path).Path
  if ($p.Length -ge 3 -and $p[1] -eq ":" -and ($p[2] -eq [char]92 -or $p[2] -eq [char]47)) {
    $drive = $p.Substring(0, 1).ToLower()
    $rest = $p.Substring(2).Replace('\', '/')
    return "/mnt/$drive$rest"
  }
  throw "Unsupported path for WSL conversion: $p"
}

function Get-LatestCaptureDir() {
  $base = Resolve-Path ".\\out\\godot_capture" -ErrorAction SilentlyContinue
  if (-not $base) { return $null }
  $dirs = Get-ChildItem -Path $base.Path -Directory | Sort-Object Name -Descending
  if ($dirs.Count -eq 0) { return $null }
  return $dirs[0].FullName
}

if ($CaptureDir -eq "") {
  $latest = Get-LatestCaptureDir
  if (-not $latest) { throw "No capture directories found under out\\godot_capture" }
  $CaptureDir = $latest
}

if (-not (Test-Path $CaptureDir)) { throw "CaptureDir not found: $CaptureDir" }

$mic = Join-Path $CaptureDir "raw_mic.wav"
$ref = Join-Path $CaptureDir "ref_signal.wav"
$clean = Join-Path $CaptureDir "clean.wav"
$vadDir = Join-Path $CaptureDir "vad"

if (-not (Test-Path $mic)) { throw "Missing: $mic" }
if (-not (Test-Path $ref)) { throw "Missing: $ref" }
New-Item -ItemType Directory -Force -Path $vadDir | Out-Null

$repoRootWin = (Resolve-Path ".").Path
$repoRootWsl = To-WslPath $repoRootWin

$micWsl = To-WslPath $mic
$refWsl = To-WslPath $ref
$cleanWsl = To-WslPath $clean
$vadWsl = To-WslPath $vadDir

Write-Host "[INFO] CaptureDir: $CaptureDir"

wsl -- bash -lc "cd '$repoRootWsl' && bash scripts/wsl/run_offline_aec.sh '$micWsl' '$refWsl' '$cleanWsl' '$DelayMs'"
if ($LASTEXITCODE -ne 0) { throw "offline_aec failed with exit code $LASTEXITCODE" }

wsl -- bash -lc "cd '$repoRootWsl' && bash scripts/wsl/run_offline_vad.sh '$cleanWsl' '$vadWsl' '$Aggressiveness'"
if ($LASTEXITCODE -ne 0) { throw "offline_vad failed with exit code $LASTEXITCODE" }

Write-Host "[OK] Wrote: $clean"
Write-Host "[OK] Wrote: $vadDir\\vad_result.txt"
Write-Host "[OK] Segments under: $vadDir"

