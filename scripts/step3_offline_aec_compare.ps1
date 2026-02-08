param(
  [string]$CaptureDir = "",
  [int]$DelayMs = 0,
  [ValidateSet("2019","2022")]
  [string]$PreferVs = "2019"
)

$ErrorActionPreference = "Stop"

function Get-RepoRootWin() {
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
if (-not (Test-Path $mic)) { throw "Missing: $mic" }
if (-not (Test-Path $ref)) { throw "Missing: $ref" }

$wslOut = Join-Path $CaptureDir ("clean_wsl_delay{0}.wav" -f $DelayMs)
$winOut = Join-Path $CaptureDir ("clean_win_delay{0}.wav" -f $DelayMs)

Write-Host "[INFO] CaptureDir: $CaptureDir"
Write-Host "[INFO] DelayMs:    $DelayMs"

pwsh -NoProfile -File (Join-Path $PSScriptRoot "step3_offline_aec.ps1") -Mic $mic -Ref $ref -Out $wslOut -DelayMs $DelayMs | Out-Host
pwsh -NoProfile -File (Join-Path $PSScriptRoot "step3_offline_aec_win.ps1") -Mic $mic -Ref $ref -Out $winOut -DelayMs $DelayMs -PreferVs $PreferVs | Out-Host

$metric = Join-Path (Get-RepoRootWin) "python\\scripts\\echo_leakage_metric.py"
if (Test-Path $metric) {
  Write-Host ""
  Write-Host "== Echo Leakage Proxy (best corr vs ref) =="
  python $metric --sig $mic --ref $ref --max-delay-ms 300 --decimate 20 | Out-Host
  python $metric --sig $wslOut --ref $ref --max-delay-ms 300 --decimate 20 | Out-Host
  python $metric --sig $winOut --ref $ref --max-delay-ms 300 --decimate 20 | Out-Host
}

Write-Host ""
Write-Host "[OK] WSL out: $wslOut"
Write-Host "[OK] WIN out: $winOut"

