# WSL scripts

这些脚本用于在 WSL2（推荐 Ubuntu 24）里编译 `webrtc-audio-processing`。

依赖源码期望放在：

- `deps/webrtc-audio-processing/`

首次在 WSL 装构建工具（推荐用 root，避免 `sudo` 交互卡住）：

```powershell
wsl -u root -- bash -lc "bash scripts/wsl/bootstrap_ubuntu.sh"
```

构建（WSL 内执行）：

```bash
bash scripts/wsl/build_webrtc.sh
```

产物约定：

- `deps/webrtc-audio-processing/install/`（头文件 + 库）

离线 AEC 工具（WSL 内执行）：

```bash
bash scripts/wsl/build_offline_aec.sh
bash scripts/wsl/run_offline_aec.sh
```

离线 VAD 切段工具（WSL 内执行）：

```bash
bash scripts/wsl/build_offline_vad.sh
bash scripts/wsl/run_offline_vad.sh
```
