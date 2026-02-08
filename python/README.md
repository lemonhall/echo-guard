# Python workspace

用于放测试数据生成、离线评估脚本等（阶段一/二都会用）。

本阶段只提供最小的自检入口：

```powershell
python .\python\src\echo_guard\verify.py
```

如果想顺便验证 `uv` 能正常跑脚本（不会尝试装包/拉依赖）：

```powershell
pwsh -File .\scripts\verify.ps1 -SkipNative -SkipWsl -UseUv
```
