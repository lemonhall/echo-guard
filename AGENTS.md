# Agent Notes (echo-guard)

## 1) Architecture Overview

### Areas
- Spec / notes: `doc/init.md`
- Verifiers / tooling:
  - entrypoint: `scripts/verify.ps1`
  - Windows helper: `scripts/install_tools_windows.ps1`
  - WSL build: `scripts/wsl/build_webrtc.sh`
- Third-party deps: `deps/`
  - expected: `deps/webrtc-audio-processing/` (source checkout)
  - expected output: `deps/webrtc-audio-processing/install/` (headers/libs from Meson install)
- Native (C++): `cpp/`
  - build system: `cpp/CMakeLists.txt`
  - CLI stub: `cpp/src/echo_guard_cli.cpp`
- Python utilities: `python/`
  - entry: `python/src/echo_guard/verify.py` (scaffold verification)

### Data Flow (target pipeline)
```
Mic -> AEC3 (webrtc-audio-processing) -> energy VAD -> segments -> WAV
```

### Persistence
- Build artifacts live under `build/` (ignored): `build/cpp`, `build/uv-cache`
- Python venvs may appear under `python/.venv` (ignored)
- Third-party install outputs (from WSL script): `deps/webrtc-audio-processing/install/`

## 2) Code Conventions (Negative Knowledge)

- Do not add any external API/network runtime dependency to the *product path*.
  - Why: This repo is an offline/local validation harness (no ASR, no network calls).
  - Do instead: Keep algorithms local; any downloads only for dev tooling/deps.
  - Verify: Grep for `http` usage in runtime code before declaring milestones.

- Do not edit vendor sources under `deps/` (unless explicitly required).
  - Why: Makes builds non-reproducible and hard to update.
  - Do instead: Patch upstream via forks or keep minimal patch files under `patches/` (add later if needed).
  - Verify: `git diff` (if repo is under git) shows no accidental vendor edits.

- Do not rely on internet access for `scripts/verify.ps1` scaffold checks.
  - Why: Some environments block outbound sockets; verification must still work.
  - Do instead: Keep `verify` in “script mode” and avoid `pip/uv` installs unless a step explicitly needs it.
  - Verify: `pwsh -File scripts/verify.ps1 -SkipNative -SkipWsl -UseUv` succeeds.

- Do not mix responsibilities in one giant file (esp. Godot/GDExtension later).
  - Why: Makes audio pipeline debugging impossible.
  - Do instead: Keep modules split: capture -> AEC -> VAD -> export -> UI glue.
  - Verify: Each stage has a minimal CLI or script entry to test independently.

## 3) Testing Strategy

### Scaffold (no CMake / no WSL)
`pwsh -File .\scripts\verify.ps1 -SkipNative -SkipWsl`

### Scaffold + uv execution path
`pwsh -File .\scripts\verify.ps1 -SkipNative -SkipWsl -UseUv`

### Native (requires CMake)
`pwsh -File .\scripts\verify.ps1 -SkipWsl`

### WSL deps build (requires WSL + meson+ninja inside WSL)
Run inside WSL:
`bash scripts/wsl/build_webrtc.sh`

