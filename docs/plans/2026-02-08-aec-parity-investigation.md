# AEC Parity (WSL2 static .a vs Windows .dll) Investigation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Identify why AEC quality is good in WSL2 (GCC static) but worse in Windows (MSVC DLL + Godot runtime), and produce a reproducible offline A/B comparison that isolates build flags vs real-time capture/timing.

**Architecture:** Treat this as a multi-boundary bug (build flags → preprocessor macros → DSP code paths → audio frame timing). First gather hard evidence from build systems (actual compiler/linker invocations + macro sets), then isolate runtime variables by running the exact same WAV input through both builds.

**Tech Stack:** MSVC/clang-cl, CMake/SCons/Meson, webrtc-audio-processing (APM/AEC3), Godot 4 GDExtension, PowerShell, WSL2 Ubuntu.

---

### Task 1: Inventory build entrypoints and configs

**Files:**
- Inspect: `scripts/verify.ps1`
- Inspect: `cpp/CMakeLists.txt`
- Inspect: `python/src/echo_guard/verify.py`
- Inspect: any `SConstruct`, `*.scons`, `meson.build`, `meson_options.txt`

**Step 1: Find build/config files (Windows)**

Run:
- `pwsh -NoProfile -Command "Get-ChildItem -Recurse -Depth 6 -File -Include CMakeLists.txt,SConstruct,*.scons,meson.build,meson_options.txt,*.vcxproj,*.sln | Select-Object FullName"`

Expected: a short list of build entrypoints and any Godot/SCons extension build scripts.

---

### Task 2: Capture *actual* compiler flags and defines (Windows)

**Files:**
- Modify/Create: `scripts/dump_build_flags.ps1` (if missing)

**Step 1: If using CMake, emit compile_commands**

Run:
- `cmake -S cpp -B build/cpp -DCMAKE_BUILD_TYPE=Release -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`
- `cmake --build build/cpp --config Release --verbose`

Expected: `build/cpp/compile_commands.json` exists and build logs show `/O2` (or equivalent) and `/fp:*`.

**Step 2: If using MSBuild/VS, capture verbose logs**

Run:
- `msbuild <path-to-sln-or-vcxproj> /p:Configuration=Release /v:diag > build/msbuild.diag.log`

Expected: log includes full `cl.exe` command lines and `/D...` defines.

**Step 3: Extract defines for a single translation unit**

Option A (clang-cl recommended):
- `clang-cl -dM -E <same-includes-and-defines> -xc++ NUL > build/macros.win.txt`

Option B (MSVC):
- build with `/P` and inspect generated `.i` for defines that influence code paths.

---

### Task 3: Capture build flags and defines (WSL2)

**Files:**
- Inspect: `scripts/wsl/build_webrtc.sh`

**Step 1: Build with verbose output**

Run inside WSL2:
- `bash scripts/wsl/build_webrtc.sh`
- If Meson/Ninja: `ninja -C <builddir> -v`

Expected: compile lines show `-O2/-O3`, `-ffast-math` (if any), and any `-DWEBRTC_*` defines.

**Step 2: Extract macro set**

Run inside WSL2:
- `g++ -dM -E -x c++ /dev/null > build/macros.wsl.txt`

Expected: baseline macro set for the compiler; additionally capture per-target flags from build logs.

---

### Task 4: Diff platform-specific code paths inside webrtc-audio-processing

**Files:**
- Inspect (do not edit): `deps/webrtc-audio-processing/**`

**Step 1: Search platform conditionals**

Run:
- `rg -n \"\\bWEBRTC_(WIN|POSIX)\\b\" deps/webrtc-audio-processing`
- `rg -n \"#\\s*if(n)?def\\s+WEBRTC_(WIN|POSIX)\" deps/webrtc-audio-processing`

Expected: list of locations to check in AEC3/NS/AGC and audio buffer utilities.

**Step 2: Focus review on AEC3 + audio frame plumbing**

Prioritize directories containing:
- `aec3`
- `audio_processing`
- `rtc_base`

Expected: identify any Windows-only implementations that could change numerical behavior or timing assumptions.

---

### Task 5: Build an offline A/B test harness (eliminate realtime capture differences)

**Files:**
- Modify: `cpp/src/echo_guard_cli.cpp` (or add a dedicated tool under `cpp/src/tools/`)
- Modify: `python/src/echo_guard/verify.py` (optional runner)

**Step 1: Create an offline CLI that:**
- Loads a known input WAV (far-end + near-end or a mixed input depending on pipeline design)
- Processes in strict 10ms frames
- Writes output WAV and (optionally) debug metrics (ERLE, residual energy, etc.)

**Step 2: Run the exact same WAV through:**
- WSL2 build (static lib)
- Windows build (DLL build, but run the same processing code path)

Expected: if offline outputs match (or are close), the primary culprit is realtime I/O / buffering / Godot config; if they differ materially, culprit is build flags/macros/SIMD/fp model.

---

### Task 6: Runtime timing audit (only if offline matches)

**Files:**
- Modify: GDExtension processor wrapper (where audio callback is handled)

**Step 1: Log/validate invariants in the realtime path**
- Frame size always equals `sample_rate / 100` samples
- No dropped/duplicated frames
- Accurate far-end vs near-end alignment
- Stable delay estimator inputs

Expected: detect buffer jitter, frame misalignment, or wrong sample rate/buffer assumptions in Windows/Godot.

