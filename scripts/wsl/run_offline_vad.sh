#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

in="${1:-$root_dir/out/test_data/clean.wav}"
out_dir="${2:-$root_dir/out/test_data/vad}"
aggr="${3:-2}"

bash "$root_dir/scripts/wsl/build_offline_vad.sh"

bin="$root_dir/build/wsl/offline_vad/offline_vad"
if [[ ! -x "$bin" ]]; then
  echo "[ERROR] Missing binary: $bin" >&2
  exit 1
fi

mkdir -p "$out_dir"
"$bin" --in "$in" --out-dir "$out_dir" --aggr "$aggr"

