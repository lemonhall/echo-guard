param(
  [double]$DurationS = 8.0,
  [int]$DelayMs = 0,
  [ValidateRange(0, 3)]
  [int]$Aggressiveness = 2
)

$ErrorActionPreference = "Stop"

pwsh -File .\scripts\step23.ps1 -DurationS $DurationS -DelayMs $DelayMs
if ($LASTEXITCODE -ne 0) { throw "Step2/3 failed with exit code $LASTEXITCODE" }

pwsh -File .\scripts\step4_vad.ps1 -In "out\\test_data\\clean.wav" -OutDir "out\\test_data\\vad" -Aggressiveness $Aggressiveness
if ($LASTEXITCODE -ne 0) { throw "Step4 failed with exit code $LASTEXITCODE" }

Write-Host ""
Write-Host "[OK] Step 2/3/4 complete"

