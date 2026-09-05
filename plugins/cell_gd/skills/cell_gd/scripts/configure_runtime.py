#!/usr/bin/env python3
"""Detect the local Cell_ppt host and persist a non-secret runtime profile."""

from __future__ import annotations

import argparse
import json
import platform
import sys
import tempfile
from pathlib import Path


def windows_progid_exists(progid: str) -> bool:
    if platform.system() != "Windows":
        return False
    try:
        import winreg

        with winreg.OpenKey(winreg.HKEY_CLASSES_ROOT, progid):
            return True
    except OSError:
        return False


def detect() -> dict:
    system = platform.system()
    powerpoint = windows_progid_exists("PowerPoint.Application")
    wps = windows_progid_exists("KWPP.Application") or windows_progid_exists("WPP.Application")
    mac_powerpoint = Path("/Applications/Microsoft PowerPoint.app").exists() if system == "Darwin" else False
    if system == "Windows" and powerpoint:
        backend = "powerpoint-live-com"
        host = "powerpoint"
    elif system == "Windows" and wps:
        backend = "wps-live-com-experimental"
        host = "wps"
    else:
        backend = "editable-ooxml-saved-pptx"
        host = "ooxml"
    return {
        "schemaVersion": 1,
        "platform": system.lower(),
        "backend": backend,
        "host": host,
        "powerPointRegistered": powerpoint,
        "powerPointInstalledOnMac": mac_powerpoint,
        "wpsRegistered": wps,
        "python": f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
        "core": {
            "cacheSchema": 3,
            "ordinaryBatch": [20, 50],
            "stepDelayMs": 8,
            "filter": "remove-exact-duplicates-only",
            "order": "literal-source-back-to-front",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    profile = detect()
    if args.output:
        output = args.output.expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=output.parent, delete=False) as handle:
            json.dump(profile, handle, ensure_ascii=False, separators=(",", ":"))
            handle.write("\n")
            temporary = Path(handle.name)
        temporary.replace(output)
        profile["profilePath"] = str(output)
    if args.json:
        print(json.dumps(profile, ensure_ascii=False, separators=(",", ":")))
    else:
        print(
            "RUNTIME_CONFIG_OK|"
            f"platform={profile['platform']}|backend={profile['backend']}|host={profile['host']}|secret=false"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
