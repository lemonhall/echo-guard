# echo-guard

技术验证工程：验证本地音频链路 **Mic → WebRTC AEC3 → 能量 VAD → 导出干净人声 WAV**，并最终封装为 Godot GDExtension。

## Quickstart（验证工程骨架）

先跑“纯骨架”校验（不要求已装 CMake / 不要求 WSL）：

```powershell
pwsh -File .\scripts\verify.ps1 -SkipNative -SkipWsl
```

额外验证 `uv` 的运行路径（仍然不需要联网/不拉依赖）：

```powershell
pwsh -File .\scripts\verify.ps1 -SkipNative -SkipWsl -UseUv
```

如果你已装好 CMake（以及可选 Ninja / MSVC Build Tools），跑全量校验：

```powershell
pwsh -File .\scripts\verify.ps1
```

## 依赖（git submodule）

本仓库把 `webrtc-audio-processing` 作为 submodule 放在 `deps/webrtc-audio-processing`。

首次拉取（或 clone 后补拉）：

```powershell
git submodule update --init --recursive
```

强制要求依赖就绪（把缺失视为失败）：

```powershell
pwsh -File .\scripts\verify.ps1 -RequireDeps
```

## WSL 编译 webrtc-audio-processing（V1 前置）

首次在 WSL 安装构建工具（避免 `sudo` 卡在输密码）：

```powershell
wsl -u root -- bash -lc "bash scripts/wsl/bootstrap_ubuntu.sh"
```

编译 + 安装到 `deps/webrtc-audio-processing/install/`：

```powershell
wsl -- bash -lc "cd /mnt/e/development/echo-guard && bash scripts/wsl/build_webrtc.sh"
```

强制要求 WSL 工具链 + 已编译产物：

```powershell
pwsh -File .\scripts\verify.ps1 -RequireDeps -RequireWslTools -RequireWslBuild
```

## Step 2/3：生成测试数据 + 离线 AEC 验证

一条命令跑通（Windows 调用 WSL 编译/运行）：

```powershell
pwsh -File .\scripts\step23.ps1
```

手动分步：

```powershell
pwsh -File .\scripts\step2_generate_test_data.ps1
pwsh -File .\scripts\step3_offline_aec.ps1
python .\python\scripts\evaluate_aec.py --dir out\test_data
```

## Step 4：WebRTC VAD 切段

在 `clean.wav` 上跑 WebRTC VAD，输出逐帧标记 + 切段 WAV：

```powershell
pwsh -File .\scripts\step4_vad.ps1
```

一步跑通 Step 2/3/4：

```powershell
pwsh -File .\scripts\step234.ps1
```

## Step 6：Godot 4.6 端到端（跳过 Step 5）

准备：
- 把你的 BGM 放到：`godot/assets/audio/pixel_coffee_break.mp3`（本 repo 默认忽略 mp3，不会误提交）
- Godot 路径：`E:\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64*.exe`

运行 Godot 验证场景：

```powershell
pwsh -File .\scripts\step6_run_godot.ps1 -Console
```

在 Godot 里用 UI 按钮 `Start/Stop + Export`（或快捷键 `R`）录制并导出 `raw_mic.wav` + `ref_signal.wav` 到 `out/godot_capture/<timestamp>/`。

处理（调用现有 WSL 离线 AEC+VAD，生成 `clean.wav` + `vad/segment_*.wav`）：

```powershell
pwsh -File .\scripts\step6_process_capture.ps1
```

处理完成后回到 Godot，点 `Reload Segments`，再选中 `segment_*.wav` 点 `Play Selected` 回放。

## 文档

- 方案：`doc/init.md`
- 开发/构建入口：`scripts/verify.ps1`
