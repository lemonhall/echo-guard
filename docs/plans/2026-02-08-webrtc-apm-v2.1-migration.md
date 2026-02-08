# WebRTC AudioProcessing v0.3.1 → v2.1 Migration Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Replace the legacy `cross-platform/webrtc-audio-processing` v0.3.1 submodule with the official `pulseaudio/webrtc-audio-processing` v2.1 (AEC3), and migrate all repo code to the new config/builder API (no manual delay injection).

**Architecture:** Keep the dependency at `deps/webrtc-audio-processing` (git submodule) and consume it via Meson installs (`install/` in WSL, `install-win/` on Windows). Update tool + GDExtension code to use `webrtc::AudioProcessing::Config` + `webrtc::AudioProcessingBuilder().SetConfig(...).Create()`.

**Tech Stack:** Git submodules, Meson/Ninja (WSL + Windows), C++17, PowerShell, WebRTC AudioProcessing (AEC3).

---

### Task 1: Switch submodule to official v2.1

**Files:**
- Modify: `.gitmodules`
- Modify: `deps/webrtc-audio-processing` (submodule pointer)

**Steps:**
1. Ensure the old submodule is clean (no vendor edits inside).
2. `git submodule deinit -f deps/webrtc-audio-processing`
3. `git rm -f deps/webrtc-audio-processing`
4. Remove leftover module dir: `.git/modules/deps/webrtc-audio-processing`
5. Add official submodule: `https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing.git`
6. Checkout tag `v2.1` inside the submodule and stage `.gitmodules` + submodule pointer.
7. Verify: `git submodule status` shows `deps/webrtc-audio-processing (v2.1)`

---

### Task 2: Make build/verify scripts resilient to v2.x outputs

**Files:**
- Modify: `scripts/verify.ps1`
- Modify: `scripts/wsl/build_offline_aec.sh`
- Modify: `scripts/wsl/build_offline_vad.sh`
- Modify: `scripts/step3_offline_aec_win.ps1`
- Modify: `scripts/step7_run_realtime.ps1`

**Steps:**
1. Detect and warn if the submodule is not `v2.1` (fast failure).
2. When checking for installed artifacts, accept both legacy and v2.x library names.
3. Prefer `pkg-config --libs --static webrtc-audio-processing` (WSL scripts) to pick up any new link deps (e.g. abseil).
4. Verify: `pwsh -File scripts/verify.ps1 -SkipNative -SkipWsl` prints submodule rev `v2.1...` and no warnings.

---

### Task 3: Migrate offline AEC tool to AEC3 API (remove manual delay)

**Files:**
- Modify: `cpp/tools/offline_aec.cpp`

**Steps:**
1. Remove use of `apm->echo_cancellation()` and `apm->set_stream_delay_ms(...)`.
2. Create APM with:
   - `webrtc::AudioProcessing::Config config;`
   - `config.echo_canceller.enabled = true;`
   - plus NS/HPF/GC modules as desired
   - `auto apm = webrtc::AudioProcessingBuilder().SetConfig(config).Create();`
3. Update any includes to match v2.1 header layout.
4. Keep the processing loop: `ProcessReverseStream(...)` then `ProcessStream(...)`.
5. Verify: tool builds (WSL or Windows path) and runs on existing test data.

---

### Task 4: Migrate Godot processor to AEC3 API (remove delay plumbing)

**Files:**
- Modify: `godot/native/echo_guard/src/echo_guard_processor.cpp`
- Modify: `godot/native/echo_guard/src/echo_guard_processor.h` (if needed)
- Modify: any GDScript glue that exposes `set_stream_delay_ms` (if present)

**Steps:**
1. Remove `echo_cancellation()` usage and any delay setter usage.
2. Create APM via builder + config.
3. If any public API exposes delay/extended filter/delay-agnostic knobs, delete or no-op them per `doc/迁移.md`.
4. Verify: native build still succeeds and runtime path no longer references old API symbols.

---

### Task 5: Validation

**Steps:**
1. `pwsh -File scripts/verify.ps1 -SkipNative -SkipWsl`
2. `pwsh -File scripts/verify.ps1 -SkipNative -SkipWsl -UseUv`
3. `rg -n "echo_cancellation\\(|set_stream_delay_ms\\(" -S .` returns nothing outside `doc/` files.

