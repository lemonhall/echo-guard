# Native (C++) workspace

阶段一/二的 CLI 与后续 AEC/VAD 核心会逐步落在这里。

当前只提供一个可编译的 CLI stub（便于验证工具链与目录结构）。

构建（Windows）：

```powershell
cmake -S .\cpp -B .\build\cpp
cmake --build .\build\cpp
```

然后运行：

```powershell
.\build\cpp\Debug\echo_guard_cli.exe --version
```

