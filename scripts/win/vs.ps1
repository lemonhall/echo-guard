param()

$ErrorActionPreference = "Stop"

function Get-VsWherePath() {
  $p = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
  if (Test-Path $p) { return $p }
  return $null
}

function Get-VsInstallationPath {
  param(
    [ValidateSet("2019","2022")]
    [string]$Prefer = "2019"
  )

  $vswhere = Get-VsWherePath
  if (-not $vswhere) {
    throw "vswhere.exe not found. Install Visual Studio Installer or Build Tools."
  }

  $requires = "Microsoft.VisualStudio.Component.VC.Tools.x86.x64"

  $versionRange = if ($Prefer -eq "2019") { "[16.0,17.0)" } else { "[17.0,18.0)" }
  $path = & $vswhere -products * -latest -requires $requires -version $versionRange -property installationPath
  if ($LASTEXITCODE -eq 0 -and $path) { return $path.Trim() }

  # Fallback: any version with VC tools.
  $path = & $vswhere -products * -latest -requires $requires -property installationPath
  if ($LASTEXITCODE -ne 0 -or -not $path) {
    throw "No Visual Studio instance found with VC Tools (x86/x64). Install 'Desktop development with C++'."
  }
  return $path.Trim()
}

function Get-VsDevCmdPath {
  param(
    [ValidateSet("2019","2022")]
    [string]$Prefer = "2019"
  )
  $vs = Get-VsInstallationPath -Prefer $Prefer
  $p = Join-Path $vs "Common7\Tools\VsDevCmd.bat"
  if (-not (Test-Path $p)) {
    throw "VsDevCmd.bat not found: $p"
  }
  return $p
}

function Invoke-InVsDevCmd {
  param(
    [Parameter(Mandatory)]
    [string]$Command,
    [ValidateSet("2019","2022")]
    [string]$Prefer = "2019",
    [ValidateSet("x64","x86")]
    [string]$Arch = "x64"
  )

  $vsdev = Get-VsDevCmdPath -Prefer $Prefer
  $archArg = if ($Arch -eq "x64") { "amd64" } else { "x86" }

  # Use cmd.exe to apply the VS environment, then run the requested command.
  # NOTE: Keep everything in a single cmd /c string so env vars are applied.
  $cmd = 'call "{0}" -arch={1} -host_arch=amd64 >nul && {2}' -f $vsdev, $archArg, $Command
  cmd /v:on /c $cmd | Out-Host
  return [int]$LASTEXITCODE
}
