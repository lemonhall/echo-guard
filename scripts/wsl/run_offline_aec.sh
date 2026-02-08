#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

mic="${1:-$root_dir/out/test_data/mic_mixed.wav}"
ref="${2:-$root_dir/out/test_data/ref_signal.wav}"
out="${3:-$root_dir/out/test_data/clean.wav}"
delay_ms="${4:-0}"

bash "$root_dir/scripts/wsl/build_offline_aec.sh"

bin="$root_dir/build/wsl/offline_aec/offline_aec"
if [[ ! -x "$bin" ]]; then
  echo "[ERROR] Missing binary: $bin" >&2
  exit 1
fi

mkdir -p "$(dirname "$out")"
"$bin" --mic "$mic" --ref "$ref" --out "$out" --delay-ms "$delay_ms"

