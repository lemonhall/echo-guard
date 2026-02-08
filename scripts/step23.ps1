param(
  [double]$DurationS = 8.0,
  [int]$DelayMs = 0
)

$ErrorActionPreference = "Stop"

pwsh -File .\scripts\step2_generate_test_data.ps1 -OutDir "out\\test_data" -DurationS $DurationS
if ($LASTEXITCODE -ne 0) { throw "Step2 failed with exit code $LASTEXITCODE" }

pwsh -File .\scripts\step3_offline_aec.ps1 -DelayMs $DelayMs
if ($LASTEXITCODE -ne 0) { throw "Step3 failed with exit code $LASTEXITCODE" }

python .\python\scripts\evaluate_aec.py --dir out\\test_data
if ($LASTEXITCODE -ne 0) { throw "evaluate_aec failed with exit code $LASTEXITCODE" }
