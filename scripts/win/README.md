# Windows (MSVC) scripts

These scripts help you use your installed Visual Studio toolchain (MSVC) from PowerShell.

## Probe MSVC

Run:

`pwsh -NoProfile -File .\scripts\step7_probe_msvc.ps1`

If this prints `cl /Bv` output and ends with `[OK]`, your VS environment is usable for Step 7 (GDExtension build).

## How it works

- `scripts/win/vs.ps1` locates VS via `vswhere.exe`.
- It runs your command under `VsDevCmd.bat` so `cl/link/msbuild` are on PATH.

