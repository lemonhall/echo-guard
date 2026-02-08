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

## 文档

- 方案：`doc/init.md`
- 开发/构建入口：`scripts/verify.ps1`
