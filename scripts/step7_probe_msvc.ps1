param(
  [ValidateSet("2019","2022")]
  [string]$Prefer = "2019"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "win\\vs.ps1")

Write-Host "Probing MSVC toolchain via VsDevCmd..."
$code = Invoke-InVsDevCmd -Prefer $Prefer -Command "where cl && where link && where msbuild && cl /Bv"
# NOTE: `cl /Bv` prints version but returns errorlevel=2 when no inputs are provided.
if ($code -ne 0 -and $code -ne 2) { throw "MSVC probe failed (exit=$code)" }

Write-Host ""
Write-Host "[OK] MSVC toolchain is callable from scripts."
