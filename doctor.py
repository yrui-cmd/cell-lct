#!/usr/bin/env python3
"""Cross-platform non-mutating cell_gd diagnostics."""

from __future__ import annotations

import argparse
import importlib.metadata
import json
import platform
import subprocess
import sys
from pathlib import Path


LOCKED = {"python-pptx": "1.0.2", "fonttools": "4.61.1", "shapely": "2.1.2"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--verify-api", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    skill = root / "plugins" / "cell_gd" / "skills" / "cell_gd"
    required = [
        skill / "SKILL.md",
        skill / "scripts" / "run_cell_ppt.ps1",
        skill / "scripts" / "run_cell_ppt_ooxml.py",
        skill / "scripts" / "xiaomiao.py",
        skill / "scripts" / "set_xiaomiao_key.py",
    ]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise SystemExit("Missing: " + ", ".join(missing))
    if not ((3, 11) <= sys.version_info[:2] < (3, 15)):
        raise SystemExit("Python 3.11-3.14 is required.")
    versions = {name: importlib.metadata.version(name) for name in LOCKED}
    if versions != LOCKED:
        raise SystemExit(f"Locked dependency mismatch: {versions}")

    system = platform.system()
    profile_proc = subprocess.run(
        [sys.executable, str(skill / "scripts" / "configure_runtime.py"), "--json"],
        text=True,
        capture_output=True,
        check=True,
    )
    profile = json.loads(profile_proc.stdout)
    api_ok = None
    if args.verify_api:
        if system == "Windows":
            proc = subprocess.run(
                ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(skill / "scripts" / "xiaomiao.ps1"), "verify"],
                text=True,
                capture_output=True,
                check=False,
            )
        else:
            proc = subprocess.run(
                [sys.executable, str(skill / "scripts" / "xiaomiao.py"), "verify"],
                text=True,
                capture_output=True,
                check=False,
            )
        api_ok = proc.returncode == 0
        if not api_ok:
            raise SystemExit("Xiaomiao API authentication failed.")
    result = {
        "ok": True,
        "skill": "cell_gd",
        "platform": system.lower(),
        "backend": profile["backend"],
        "host": profile["host"],
        "powerPointRegistered": profile["powerPointRegistered"],
        "macPowerPointInstalled": profile["powerPointInstalledOnMac"],
        "wpsRegistered": profile["wpsRegistered"],
        "apiVerified": args.verify_api,
        "apiAuthenticated": api_ok,
    }
    if args.json:
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    else:
        print("DOCTOR_OK|" + "|".join(f"{key}={str(value).lower()}" for key, value in result.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
