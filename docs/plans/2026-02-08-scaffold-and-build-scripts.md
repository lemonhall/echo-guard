# Scaffold & Build Scripts Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 建立可重复验证的工程骨架（目录结构 + 依赖放置约定 + 构建/验证脚本），让“环境是否齐全/骨架是否连通”可以一条命令验证。

**Architecture:** 顶层只做“工具链与工程连通性”的验证；算法验证（AEC/VAD）后续逐步加。Python 用 `uv run` 做最小自检；Native 用 CMake 生成一个可执行的 CLI stub，后续再接入 `webrtc-audio-processing`。

**Tech Stack:** PowerShell、Python（uv）、C++（CMake）、WSL2（Meson/Ninja 用于 webrtc-audio-processing）。

### Task 1: Add baseline repo layout and docs

**Files:**
- Create: `README.md`
- Create: `.gitignore`
- Create: `deps/README.md`
- Create: `cpp/README.md`
- Create: `python/README.md`

**Step 1: Add minimal README and quickstart**
- Verify: `README.md` 中包含 `scripts/verify.ps1` 的调用示例

**Step 2: Add ignore rules**
- Verify: `.gitignore` 覆盖 `build/`、`.venv/`、`__pycache__/`

### Task 2: Add a single entrypoint verifier script

**Files:**
- Create: `scripts/verify.ps1`
- Create: `scripts/install_tools_windows.ps1`

**Step 1: Implement `scripts/verify.ps1`**
- Verify: `pwsh -File scripts/verify.ps1 -SkipNative -SkipWsl` 可运行并返回 0

**Step 2: Add Windows tool install helper**
- Verify: 脚本只做引导/提示，不强依赖本机能联网

### Task 3: Add a minimal Python project (uv) with smoke-check

**Files:**
- Create: `python/pyproject.toml`
- Create: `python/src/echo_guard/__init__.py`
- Create: `python/src/echo_guard/verify.py`

**Step 1: Implement `echo_guard.verify`**
- Verify: `uv run --project python python -m echo_guard.verify` 返回 0

### Task 4: Add native (C++) stub project for future AEC integration

**Files:**
- Create: `cpp/CMakeLists.txt`
- Create: `cpp/src/echo_guard_cli.cpp`

**Step 1: CMake project builds a CLI stub**
- Verify (after installing CMake): `cmake -S cpp -B build/cpp && cmake --build build/cpp`

### Task 5: Add WSL build scripts placeholders for webrtc-audio-processing

**Files:**
- Create: `scripts/wsl/README.md`
- Create: `scripts/wsl/build_webrtc.sh`

**Step 1: Script documents expected deps layout**
- Verify: `scripts/wsl/build_webrtc.sh` 对缺少 `deps/webrtc-audio-processing` 给出清晰报错

