param(
  [string]$Mic = "out\\test_data\\mic_mixed.wav",
  [string]$Ref = "out\\test_data\\ref_signal.wav",
  [string]$Out = "out\\test_data\\clean.wav",
  [int]$DelayMs = 0
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

$outDir = Split-Path $Out -Parent
if ($outDir -and -not (Test-Path $outDir)) {
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

$repoRootWin = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repoRootWsl = To-WslPath $repoRootWin

$micWsl = To-WslPath $Mic
$refWsl = To-WslPath $Ref
$outWsl = To-WslPath $OutDir
$outFile = Split-Path $Out -Leaf
$outWslFull = "$outWsl/$outFile"

wsl -- bash -lc "cd '$repoRootWsl' && bash scripts/wsl/run_offline_aec.sh '$micWsl' '$refWsl' '$outWslFull' '$DelayMs'"
if ($LASTEXITCODE -ne 0) { throw "WSL offline_aec failed with exit code $LASTEXITCODE" }

Write-Host "[OK] Wrote: $Out"
