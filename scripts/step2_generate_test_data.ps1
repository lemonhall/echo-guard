param(
  [string]$OutDir = "out\\test_data",
  [double]$DurationS = 8.0
)

$ErrorActionPreference = "Stop"

python .\python\scripts\generate_test_data.py --out-dir $OutDir --duration-s $DurationS

