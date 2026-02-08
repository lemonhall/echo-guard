# echo-guard (Godot 4.6)

打开项目：`godot/project.godot`（主场景：`res://scenes/main.tscn`）

## 使用

- BGM（可选）：`res://assets/audio/pixel_coffee_break.mp3`（该 mp3 默认被 `.gitignore` 忽略）
- UI：
  - `Start (R)`：开始录制（抓取 BGM 参考信号 + 麦克风）
  - `Stop + Export (R)`：停止并导出 WAV + 切段
  - `Rescan Segments`：刷新 `segment_*.wav` 列表
  - `Play Selected`：回放切段
  - `Monitor mic (hear yourself)`：默认关闭（避免啸叫/回授）

导出位置（默认）：`out/godot_capture/<timestamp>/`

导出文件：
- `ref_signal.wav`
- `raw_mic.wav`
- `clean_native.wav`
- `vad_native/vad_result.txt`
- `vad_native/segment_###.wav`
