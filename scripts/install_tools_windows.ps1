param(
  [switch]$InstallCmake,
  [switch]$InstallNinja
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

Write-Host ""
Write-Host "Done. Re-open your terminal so PATH updates take effect."

