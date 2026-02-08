param(
  [string]$Mic = "out\\test_data\\mic_mixed.wav",
  [string]$Ref = "out\\test_data\\ref_signal.wav",
  [string]$Out = "out\\test_data\\clean_win.wav",
  [int]$DelayMs = 0,
  [ValidateSet("2019","2022")]
  [string]$PreferVs = "2019",
  [switch]$Rebuild
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "win\\vs.ps1")

function Require-Path([string]$p) {
  if (-not (Test-Path $p)) { throw "Missing: $p" }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $repoRoot
try {
  Require-Path $Mic
  Require-Path $Ref

  $webrtcDir = Join-Path $repoRoot "deps\\webrtc-audio-processing"
  $webrtcInc = Join-Path $webrtcDir "install-win\\include\\webrtc_audio_processing"
  $webrtcLib = Join-Path $webrtcDir "install-win\\lib\\libwebrtc_audio_processing.a"

  if (-not (Test-Path $webrtcLib)) {
    Write-Host "[INFO] Building webrtc-audio-processing for Windows (install-win missing)..."
    & (Join-Path $PSScriptRoot "step7_build_webrtc_win.ps1") -PreferVs $PreferVs -Config release -Reconfigure | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "step7_build_webrtc_win.ps1 failed (exit=$LASTEXITCODE)" }
  }

  Require-Path $webrtcInc
  Require-Path $webrtcLib

  $outDir = Split-Path $Out -Parent
  if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  }

  $buildDir = Join-Path $repoRoot "build\\win\\offline_aec"
  New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

  $src = Join-Path $repoRoot "cpp\\tools\\offline_aec.cpp"
  Require-Path $src

  $exe = Join-Path $buildDir "offline_aec.exe"

  if ($Rebuild -and (Test-Path $exe)) {
    Remove-Item $exe -Force
  }

  if (-not (Test-Path $exe)) {
    Write-Host "[INFO] Building: $exe"
    $obj = Join-Path $buildDir "offline_aec.obj"
    if (Test-Path $obj) { Remove-Item $obj -Force }

    $compile = @(
      "cl",
      "/nologo",
      "/std:c++17",
      "/O2",
      "/MT",
      "/EHsc",
      "/utf-8",
      "/DWEBRTC_WIN",
      "/DWEBRTC_AUDIO_PROCESSING_ONLY_BUILD",
      "/D_WIN32",
      "/D_WINSOCKAPI_",
      "/DNOMINMAX",
      "/DWEBRTC_NS_FLOAT=1",
      "/I""$webrtcInc""",
      "/c",
      """$src""",
      "/Fo""$obj"""
    ) -join " "

    $link = @(
      "link",
      "/nologo",
      """$obj""",
      """$webrtcLib""",
      "winmm.lib",
      "/OUT:""$exe"""
    ) -join " "

    $cmd = 'cd /d "{0}" && {1} && {2}' -f $buildDir, $compile, $link
    $code = Invoke-InVsDevCmd -Prefer $PreferVs -Command $cmd
    if ($code -ne 0) { throw "Build failed (exit=$code)" }
  }

  Write-Host "[INFO] Running offline AEC (Windows): delay_ms=$DelayMs"
  & $exe --mic $Mic --ref $Ref --out $Out --delay-ms $DelayMs
  if ($LASTEXITCODE -ne 0) { throw "offline_aec.exe failed (exit=$LASTEXITCODE)" }

  Write-Host "[OK] Wrote: $Out"
} finally {
  Pop-Location
}
