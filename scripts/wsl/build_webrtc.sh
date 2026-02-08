#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
webrtc_dir="$root_dir/deps/webrtc-audio-processing"

if [[ ! -d "$webrtc_dir" ]]; then
  echo "[ERROR] Missing: $webrtc_dir" >&2
  echo "        Put webrtc-audio-processing sources under deps/ (see deps/README.md)" >&2
  exit 1
fi

cd "$webrtc_dir"

if ! command -v meson >/dev/null 2>&1; then
  echo "[ERROR] meson not found in WSL. Install it first (e.g. apt install meson)." >&2
  exit 1
fi

if ! command -v ninja >/dev/null 2>&1; then
  echo "[ERROR] ninja not found in WSL. Install it first (e.g. apt install ninja-build)." >&2
  exit 1
fi

if [[ ! -d build ]]; then
  meson setup build --prefix="$PWD/install"
fi

meson compile -C build
meson install -C build

echo "[OK] Installed to: $webrtc_dir/install"

