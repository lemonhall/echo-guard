param(
  [string]$In = "out\\test_data\\clean.wav",
  [string]$OutDir = "out\\test_data\\vad",
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

if (-not (Test-Path $In)) { throw "Missing input WAV: $In" }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

$repoRootWin = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repoRootWsl = To-WslPath $repoRootWin

$inWsl = To-WslPath $In
$outDirWsl = To-WslPath $OutDir

wsl -- bash -lc "cd '$repoRootWsl' && bash scripts/wsl/run_offline_vad.sh '$inWsl' '$outDirWsl' '$Aggressiveness'"
if ($LASTEXITCODE -ne 0) { throw "WSL offline_vad failed with exit code $LASTEXITCODE" }

Write-Host "[OK] Wrote: $OutDir\\vad_result.txt"
