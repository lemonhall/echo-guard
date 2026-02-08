#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
webrtc_dir="$root_dir/deps/webrtc-audio-processing"

pc_dir="$webrtc_dir/install/lib/x86_64-linux-gnu/pkgconfig"
if [[ ! -f "$pc_dir/webrtc-audio-processing.pc" ]]; then
  echo "[ERROR] Missing pkg-config file: $pc_dir/webrtc-audio-processing.pc" >&2
  echo "        Build/install webrtc first:" >&2
  echo "          bash scripts/wsl/build_webrtc.sh" >&2
  exit 1
fi

if ! command -v g++ >/dev/null 2>&1; then
  echo "[ERROR] g++ not found (install build-essential)." >&2
  exit 1
fi

if ! command -v pkg-config >/dev/null 2>&1; then
  echo "[ERROR] pkg-config not found." >&2
  exit 1
fi

export PKG_CONFIG_PATH="$pc_dir:${PKG_CONFIG_PATH:-}"

out_dir="$root_dir/build/wsl/offline_aec"
mkdir -p "$out_dir"

src="$root_dir/cpp/tools/offline_aec.cpp"
out="$out_dir/offline_aec"
lib="$webrtc_dir/install/lib/x86_64-linux-gnu/libwebrtc_audio_processing.a"

if [[ ! -f "$lib" ]]; then
  echo "[ERROR] Missing library: $lib" >&2
  echo "        Run: bash scripts/wsl/build_webrtc.sh" >&2
  exit 1
fi

echo "[INFO] Building: $out"
g++ -O2 -std=c++17 \
  $(pkg-config --cflags webrtc-audio-processing) \
  "$src" "$lib" -o "$out" \
  -lrt -pthread

echo "[OK] Built: $out"
