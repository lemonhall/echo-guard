# echo-guard

目标：一个“开箱即用”的 Godot 4.6 工程，端到端验证本地链路 **Mic + BGM → WebRTC AEC → WebRTC VAD → 导出 WAV（干净人声 + 切段）**。

本仓库已提交 Windows 预编译 GDExtension DLL，所以**运行时不依赖任何脚本/编译**。

## 运行（一步到位）

1) 准备 BGM（可选，但建议）：放到 `godot/assets/audio/pixel_coffee_break.mp3`（该 mp3 被 `.gitignore` 忽略，不会误提交）  
2) 用 Godot 4.6 打开 `godot/project.godot`，直接运行（主场景已设为 `res://scenes/main.tscn`）  
3) 在 UI 点 `Start (R)` → 说话 → `Stop + Export (R)`

导出目录：`out/godot_capture/<timestamp>/`

导出文件（核心交付物）：
- `raw_mic.wav`：原始麦克风
- `ref_signal.wav`：参考信号（BGM）
- `clean_native.wav`：GDExtension（WebRTC AEC）输出
- `vad_native/segment_###.wav` + `vad_native/vad_result.txt`：GDExtension（WebRTC VAD）切段结果

说明：`Monitor mic (hear yourself)` 默认关闭（避免啸叫/回授），需要时手动打开。

## 开发：编译/更新 GDExtension（可选）

依赖通过 git submodule 管理：

```powershell
git submodule update --init --recursive
```

首次（或升级 Godot 后）跑一次慢的初始化（会 dump `extension_api.json`，并用 `generate_bindings=yes` 全量生成/编译）：

```powershell
pwsh -NoProfile -File .\scripts\init_gdextension.ps1 -GodotDir "E:\\Godot_v4.6-stable_win64.exe"
```

日常增量编译（默认 Debug；不再 dump API，也不再 generate_bindings）：

```powershell
pwsh -NoProfile -File .\scripts\build_gdextension.ps1
```

升级 Godot / 确认需要强制重生成绑定时（慢）：用 `-RegenBindings` 显式开启（可配合 `-All` / `-ReleaseOnly`）：

```powershell
pwsh -NoProfile -File .\scripts\build_gdextension.ps1 -RegenBindings -All -GodotDir "E:\\Godot_v4.6-stable_win64.exe"
```

## 文档

- 方案/过程记录：`doc/init.md`
- Godot 工程说明：`godot/README.md`
