# deps/

第三方依赖放置目录（尽量避免改动其内容）。

当前计划依赖：

- `deps/webrtc-audio-processing/`：WebRTC AudioProcessing（AEC3 等）

建议做法（任选其一）：

1) 用 git submodule（推荐，可复现）
2) 你手动把源码放进来（最简单）
3) 写脚本 clone（需要网络）

本仓库默认采用 submodule（路径固定为 `deps/webrtc-audio-processing`）。

常用命令：

```powershell
# 首次拉取（或 clone 后补拉）
git submodule update --init --recursive

# 更新到上游最新（谨慎：会改变锁定的 commit，需要主仓库再提交一次）
git submodule update --remote --merge
```

对应的 WSL 构建脚本在：`scripts/wsl/build_webrtc.sh`
