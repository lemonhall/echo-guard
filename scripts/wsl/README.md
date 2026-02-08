# WSL scripts

这些脚本用于在 WSL2（推荐 Ubuntu 24）里编译 `webrtc-audio-processing`。

依赖源码期望放在：

- `deps/webrtc-audio-processing/`

构建（WSL 内执行）：

```bash
bash scripts/wsl/build_webrtc.sh
```

产物约定：

- `deps/webrtc-audio-processing/install/`（头文件 + 库）
