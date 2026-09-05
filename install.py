#!/usr/bin/env python3
"""Cross-platform cell_gd skill installer."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--destination", type=Path, default=Path.home() / ".codex" / "skills")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    project = Path(__file__).resolve().parent
    source = project / "plugins" / "cell_gd" / "skills" / "cell_gd"
    target_root = args.destination.expanduser().resolve()
    target = target_root / "cell_gd"
    if not source.is_dir():
        raise SystemExit(f"Plugin skill directory is missing: {source}")
    target_root.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if not args.force:
            raise SystemExit(f"Skill already exists: {target}. Re-run with --force only if replacement is intended.")
        if target.is_symlink():
            target.unlink()
        else:
            shutil.rmtree(target)
    shutil.copytree(
        source,
        target,
        ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "*.pyo"),
    )
    subprocess.run(
        [sys.executable, str(target / "scripts" / "configure_runtime.py"), "--output", str(target / "runtime-profile.json")],
        check=True,
    )
    print(f"INSTALLED|skill=cell_gd|destination={target}|copy=true")
    print("Restart Codex and start a new task before first use.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
