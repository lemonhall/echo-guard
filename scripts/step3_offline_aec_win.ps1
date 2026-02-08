param(
  [string]$Mic = "out\\test_data\\mic_mixed.wav",
  [string]$Ref = "out\\test_data\\ref_signal.wav",
  [string]$Out = "out\\test_data\\clean_win.wav",
  [ValidateSet("2019","2022")]
  [string]$PreferVs = "2019",
  [switch]$Rebuild
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "win\\vs.ps1")

function Require-Path([string]$p) {
  if (-not (Test-Path $p)) { throw "Missing: $p" }
}

function Get-WeRtcInstallWinVersion([string]$webrtcDir) {
  $pcDir = Join-Path $webrtcDir "install-win\\lib\\pkgconfig"
  $pcs = @(
    (Join-Path $pcDir "webrtc-audio-processing-2.pc"),
    (Join-Path $pcDir "webrtc-audio-processing.pc")
  ) | Where-Object { Test-Path $_ }
  $pc = $pcs | Select-Object -First 1
  if (-not $pc) { return $null }
  $line = Get-Content -ErrorAction SilentlyContinue $pc | Where-Object { $_ -match "^Version\\s*:" } | Select-Object -First 1
  if (-not $line) { return $null }
  return ($line -replace "^Version\\s*:\\s*", "").Trim()
}

function Find-WeRtcInstallWinLib([string]$webrtcDir) {
  $libDir = Join-Path $webrtcDir "install-win\\lib"
  if (-not (Test-Path $libDir)) { return $null }

  $preferred = @(
    (Join-Path $libDir "libwebrtc-audio-processing-2.a"),
    (Join-Path $libDir "libwebrtc_audio_processing.a"),
    (Join-Path $libDir "webrtc-audio-processing-2.lib"),
    (Join-Path $libDir "webrtc_audio_processing.lib")
  )

  foreach ($p in $preferred) {
    if (Test-Path $p) { return $p }
  }

  $fallback = Get-ChildItem -File -ErrorAction SilentlyContinue $libDir -Include "*.a","*.lib" |
    Where-Object { $_.Name -match "webrtc" -and $_.Name -match "audio" -and $_.Name -match "processing" } |
    Select-Object -First 1 -ExpandProperty FullName
  return $fallback
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $repoRoot
try {
  Require-Path $Mic
  Require-Path $Ref

  $webrtcDir = Join-Path $repoRoot "deps\\webrtc-audio-processing"
  $webrtcBaseInc = Join-Path $webrtcDir "install-win\\include"
  $webrtcInc = Join-Path $webrtcDir "install-win\\include\\webrtc-audio-processing-2"
  $webrtcLib = Find-WeRtcInstallWinLib $webrtcDir
  $webrtcVer = Get-WeRtcInstallWinVersion $webrtcDir
  $needWeRtcBuild = (-not (Test-Path (Join-Path $webrtcInc "api\\audio\\audio_processing.h"))) -or (-not $webrtcLib) -or (-not $webrtcVer) -or ($webrtcVer -notmatch '^2\\.1(\\.|$)')

  if ($needWeRtcBuild) {
    if (-not $webrtcVer) {
      Write-Host "[INFO] Building webrtc-audio-processing for Windows (install-win version unknown)..."
    } else {
      Write-Host ("[INFO] Building webrtc-audio-processing for Windows (install-win version={0} != 2.1)..." -f $webrtcVer)
    }
    & (Join-Path $PSScriptRoot "step7_build_webrtc_win.ps1") -PreferVs $PreferVs -Config release -Reconfigure | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "step7_build_webrtc_win.ps1 failed (exit=$LASTEXITCODE)" }
    $webrtcLib = Find-WeRtcInstallWinLib $webrtcDir
    $webrtcInc = Join-Path $webrtcDir "install-win\\include\\webrtc-audio-processing-2"
    $webrtcVer = Get-WeRtcInstallWinVersion $webrtcDir
  }

  if (-not (Test-Path (Join-Path $webrtcInc "api\\audio\\audio_processing.h"))) { throw "Missing webrtc v2 headers under: $webrtcInc (run scripts/step7_build_webrtc_win.ps1)" }
  if (-not $webrtcLib) { throw "Missing webrtc library under: $webrtcDir\\install-win\\lib" }
  if (-not $webrtcVer) { Write-Host "[WARN] Could not read webrtc-audio-processing.pc Version; build may be stale." }

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
      "/I""$webrtcBaseInc""",
      "/I""$webrtcInc""",
      "/c",
      """$src""",
      "/Fo""$obj"""
    ) -join " "

    $webrtcLibDir = Split-Path $webrtcLib -Parent
    $allLibs = @(Get-ChildItem -File -ErrorAction SilentlyContinue $webrtcLibDir -Include "*.a","*.lib")
    $mainLibName = Split-Path $webrtcLib -Leaf
    $orderedLibs = @(
      $allLibs | Where-Object { $_.Name -eq $mainLibName }
    ) + @(
      $allLibs | Where-Object { $_.Name -ne $mainLibName } | Sort-Object Name
    )
    $webrtcLinkArgs = ($orderedLibs | ForEach-Object { """$($_.FullName)""" }) -join " "

    $link = @(
      "link",
      "/nologo",
      """$obj""",
      $webrtcLinkArgs,
      "winmm.lib",
      "/OUT:""$exe"""
    ) -join " "

    $cmd = 'cd /d "{0}" && {1} && {2}' -f $buildDir, $compile, $link
    $code = Invoke-InVsDevCmd -Prefer $PreferVs -Command $cmd
    if ($code -ne 0) { throw "Build failed (exit=$code)" }
  }

  Write-Host "[INFO] Running offline AEC (Windows)"
  & $exe --mic $Mic --ref $Ref --out $Out
  if ($LASTEXITCODE -ne 0) { throw "offline_aec.exe failed (exit=$LASTEXITCODE)" }

  Write-Host "[OK] Wrote: $Out"
} finally {
  Pop-Location
}
