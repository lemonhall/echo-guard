#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" != "0" ]]; then
  echo "[ERROR] This script must run as root (to apt-get install packages)." >&2
  echo "        Run from Windows PowerShell without sudo prompts:" >&2
  echo "          wsl -u root -- bash -lc \"bash scripts/wsl/bootstrap_ubuntu.sh\"" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  git \
  meson \
  ninja-build \
  pkg-config \
  python3

echo "[OK] WSL build tools installed: meson, ninja, pkg-config, build-essential"

