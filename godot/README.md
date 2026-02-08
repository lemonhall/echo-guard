# echo-guard Godot 验证工程（Step 6）

打开项目：`godot/project.godot`

## 操作

- 运行后会自动播放 BGM：`res://assets/audio/pixel_coffee_break.mp3`
- 按 `R`：开始录制（同时抓取 BGM 参考信号 + 麦克风）
- 再按 `R`：停止并导出

导出位置（默认）：`out/godot_capture/<timestamp>/`

导出文件：
- `ref_signal.wav`
- `raw_mic.wav`

## 处理（在仓库根目录执行）

```powershell
pwsh -File .\scripts\step6_process_capture.ps1
```

生成：
- `clean.wav`
- `vad/vad_result.txt`
- `vad/segment_###.wav`

