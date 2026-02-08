param(
  [switch]$InstallCmake,
  [switch]$InstallNinja,
  [switch]$InstallMeson,
  [switch]$InstallScons
)

Write-Host "This script is a helper for Windows tool installation."
Write-Host "It uses winget when available and may require network/admin rights."
Write-Host ""

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Host "[INFO] winget not found. Install tools manually:"
  Write-Host "  - CMake: https://cmake.org/download/"
  Write-Host "  - Ninja: https://github.com/ninja-build/ninja/releases"
  exit 0
}

if ($InstallCmake) {
  Write-Host "Installing CMake..."
  winget install --id Kitware.CMake -e
}

if ($InstallNinja) {
  Write-Host "Installing Ninja..."
  winget install --id Ninja-build.Ninja -e
}

if ($InstallMeson -or $InstallScons) {
  if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "[FAIL] python not found; cannot pip-install meson/scons."
    Write-Host "       Install Python 3.12+ and re-run this script."
    exit 1
  }

  if ($InstallMeson) {
    Write-Host "Installing Meson (pip --user)..."
    python -m pip install --user --upgrade meson
  }

  if ($InstallScons) {
    Write-Host "Installing SCons (pip --user)..."
    python -m pip install --user --upgrade scons
  }

  Write-Host ""
  Write-Host "If meson/scons still not found, re-open your terminal so PATH updates take effect."
}

Write-Host ""
Write-Host "Done. Re-open your terminal so PATH updates take effect."
