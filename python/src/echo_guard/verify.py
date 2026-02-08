from __future__ import annotations

import sys
from pathlib import Path


def _repo_root() -> Path:
    here = Path(__file__).resolve()
    for parent in [here.parent, *here.parents]:
        if (parent / "doc" / "init.md").exists():
            return parent
    # Fallback: .../python/src/echo_guard/verify.py -> repo root is usually 3 parents up
    return here.parents[3]


def main() -> int:
    root = _repo_root()
    required = [
        root / "doc" / "init.md",
        root / "scripts" / "verify.ps1",
        root / "python" / "pyproject.toml",
        root / "cpp" / "CMakeLists.txt",
        root / "deps" / "README.md",
    ]

    missing = [p for p in required if not p.exists()]
    print("echo-guard scaffold verify")
    print(f"- repo_root: {root}")
    print(f"- python: {sys.version.split()[0]}")

    if missing:
        print("- status: FAIL")
        for p in missing:
            print(f"  - missing: {p}")
        return 1

    print("- status: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
