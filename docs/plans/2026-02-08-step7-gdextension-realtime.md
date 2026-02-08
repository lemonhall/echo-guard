# Step 7: Godot realtime pipeline via GDExtension (Windows/MSVC)

Date: 2026-02-08

## Goal

Move AEC+VAD processing **into the Godot process** (no `pwsh + WSL` runtime dependency) so we can do:

`BGM(ref) + mic -> AEC3 -> WebRTC VAD -> realtime segmentation -> WAV segments`

This step focuses on **Windows/MSVC** builds to match the shipped editor/runtime.

## Scope (this branch)

- Add `deps/godot-cpp` as a git submodule (branch `4.5`).
- Add a minimal GDExtension (`EchoGuardProcessor`) and make it loadable from `godot/`.
- Add a build script that:
  - dumps `extension_api.json` from the local Godot 4.6 console executable
  - builds `godot-cpp` + the extension DLL via SCons under MSVC environment

## Notes / compatibility

- Godot 4.6 editor build is used to dump `extension_api.json`.
- `godot-cpp` is pinned to `4.5` because upstream exposes stable branches up to 4.5; per its README,
  extensions targeting earlier 4.x minors should work in later minors.

## Commands

- Probe MSVC environment:
  - `pwsh -NoProfile -File .\scripts\step7_probe_msvc.ps1`
- Build extension (debug):
  - `pwsh -NoProfile -File .\scripts\step7_build_gdextension.ps1 -DebugOnly`

Outputs:
- `godot/bin/libecho_guard.windows.template_debug.x86_64.dll`

