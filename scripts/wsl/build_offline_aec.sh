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

pc_file="$pc_dir/webrtc-audio-processing.pc"
pc_version="$(sed -n 's/^Version:[[:space:]]*//p' "$pc_file" | head -n 1 | tr -d '\r')"
if [[ -n "$pc_version" && "$pc_version" != 2.1* ]]; then
  echo "[WARN] webrtc-audio-processing.pc Version=$pc_version (expected 2.1.x). Rebuild deps with scripts/wsl/build_webrtc.sh" >&2
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

lib_dir="$webrtc_dir/install/lib/x86_64-linux-gnu"
lib=""

for candidate in \
  "$lib_dir/libwebrtc-audio-processing-2.a" \
  "$lib_dir/libwebrtc_audio_processing.a"
do
  if [[ -f "$candidate" ]]; then
    lib="$candidate"
    break
  fi
done

if [[ -z "$lib" ]]; then
  shopt -s nullglob
  matches=("$lib_dir"/libwebrtc*audio*processing*.a)
  shopt -u nullglob
  if (( ${#matches[@]} > 0 )); then
    lib="${matches[0]}"
  fi
fi

if [[ -z "$lib" ]]; then
  echo "[ERROR] Missing webrtc-audio-processing static library under: $lib_dir" >&2
  echo "        Run: bash scripts/wsl/build_webrtc.sh" >&2
  exit 1
fi

echo "[INFO] Building: $out"
g++ -O2 -std=c++17 \
  $(pkg-config --cflags webrtc-audio-processing) \
  "$src" -o "$out" \
  $(pkg-config --libs --static webrtc-audio-processing) \
  -lrt -pthread

echo "[OK] Built: $out"
