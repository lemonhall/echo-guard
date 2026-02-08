param(
  [string]$CaptureDir = "",
  [int]$MaxDelayMs = 300,
  [int]$Decimate = 20,
  [double]$DelayWindowS = 3.0,
  [int]$DelayMs = -1,
  [int]$Nfft = 2048,
  [int]$Hop = 512,
  [double]$Alpha = 1.0,
  [double]$Beta = 0.01,
  [double]$GateRatio = 0.02,
  [double]$HSmooth = 0.05
)

$ErrorActionPreference = "Stop"

function Get-RepoRootWin() {
  # This script lives at <repo>/scripts/step6_spectral_subtract.ps1
  return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-LatestCaptureDir() {
  $repoRoot = Get-RepoRootWin
  $base = Resolve-Path (Join-Path $repoRoot "out\\godot_capture") -ErrorAction SilentlyContinue
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
$outName = "clean_spectral.wav"
$outPath = Join-Path $CaptureDir $outName

if (-not (Test-Path $mic)) { throw "Missing: $mic" }
if (-not (Test-Path $ref)) { throw "Missing: $ref" }

$repoRoot = Get-RepoRootWin
$py = Join-Path $repoRoot "python\\scripts\\spectral_subtract.py"
if (-not (Test-Path $py)) { throw "Missing: $py" }

Write-Host "[INFO] CaptureDir: $CaptureDir"

python $py `
  --mic $mic `
  --ref $ref `
  --out $outName `
  --max-delay-ms $MaxDelayMs `
  --decimate $Decimate `
  --delay-window-s $DelayWindowS `
  --delay-ms $DelayMs `
  --n-fft $Nfft `
  --hop $Hop `
  --alpha $Alpha `
  --beta $Beta `
  --gate-ratio $GateRatio `
  --h-smooth $HSmooth

if ($LASTEXITCODE -ne 0) { throw "spectral_subtract failed with exit code $LASTEXITCODE" }
Write-Host "[OK] Wrote: $outPath"
