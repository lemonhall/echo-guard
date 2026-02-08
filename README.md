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

## 文档

- 方案：`doc/init.md`
- 开发/构建入口：`scripts/verify.ps1`
