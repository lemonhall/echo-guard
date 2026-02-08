# Step 4 (WebRTC VAD) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在离线 AEC 输出 `clean.wav` 上跑 WebRTC 内置 VAD，输出逐帧标记文件 `vad_result.txt`，并按语音段导出 `segment_###.wav`。

**Architecture:** 在 WSL 下编译一个 `offline_vad` 小工具（直接编译 WebRTC `webrtc/common_audio/vad/*.c`），读取 `clean.wav`（mono PCM16）。若采样率不是 8/16/32k，则先下采样到 32k 供 VAD 使用；VAD 决策仍以时间轴（ms）回映到原始采样率并切段导出。

**Tech Stack:** WSL g++、WebRTC VAD（`webrtc_vad.c`）、PowerShell wrapper、Python（仅用于 Step2/3/评估）。

### Task 1: Add offline_vad tool (WSL)

**Files:**
- Create: `cpp/tools/offline_vad.cpp`
- Create: `scripts/wsl/build_offline_vad.sh`
- Create: `scripts/wsl/run_offline_vad.sh`

**Step 1: Implement CLI**
- Inputs: `--in clean.wav --out-dir <dir> [--aggr 0..3]`
- Outputs:
  - `<out-dir>/vad_result.txt` (per-frame labels)
  - `<out-dir>/segment_001.wav` ... (speech segments)

**Step 2: Verify in WSL**
- Run: `bash scripts/wsl/run_offline_vad.sh`
- Expected: creates `out/test_data/vad/vad_result.txt` and at least one `segment_*.wav`

### Task 2: Add Windows wrapper scripts

**Files:**
- Create: `scripts/step4_vad.ps1`
- Create: `scripts/step234.ps1`
- Modify: `README.md:1`

**Step 1: Implement `step4_vad.ps1`**
- Run from Windows: `pwsh -File scripts/step4_vad.ps1`

**Step 2: Add `step234.ps1` convenience**
- Run: `pwsh -File scripts/step234.ps1`

### Task 3: End-to-end validation

**Run:**
`pwsh -File scripts/step234.ps1`

**Expected:**
- `out/test_data/clean.wav` exists
- `out/test_data/vad/vad_result.txt` exists
- `out/test_data/vad/segment_001.wav` exists (and likely more)

