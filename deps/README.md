# deps/

第三方依赖放置目录（尽量避免改动其内容）。

当前计划依赖：

- `deps/webrtc-audio-processing/`：WebRTC AudioProcessing（AEC3 等）

建议做法（任选其一）：

1) 你手动把源码放进来（最简单）
2) 用 git submodule（如果你把本仓库初始化为 git）
3) 写脚本 clone（需要网络）

对应的 WSL 构建脚本在：`scripts/wsl/build_webrtc.sh`

