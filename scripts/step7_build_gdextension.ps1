param(
  [string]$GodotDir = "E:\\Godot_v4.6-stable_win64.exe",
  [string]$GodotExe = "",
  [ValidateSet("2019","2022")]
  [string]$PreferVs = "2019",
  [switch]$DebugOnly,
  [switch]$ReleaseOnly,
  [switch]$All,
  [switch]$ForceInit
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$apiFile = Join-Path $repoRoot "build\\godot_api\\extension_api.json"

# Backward-compatible wrapper:
# - If no API dump/bindings exist, run init (slow, one-time).
# - Then run the incremental build (fast, dev loop).
if ($ForceInit -or -not (Test-Path $apiFile)) {
  & (Join-Path $PSScriptRoot "init_gdextension.ps1") -GodotDir $GodotDir -GodotExe $GodotExe -PreferVs $PreferVs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$args = @("-PreferVs", $PreferVs)
if ($All) { $args += "-All" }
elseif ($ReleaseOnly) { $args += "-ReleaseOnly" }
else { $args += "-DebugOnly" } # default

& (Join-Path $PSScriptRoot "build_gdextension.ps1") @args
exit $LASTEXITCODE
