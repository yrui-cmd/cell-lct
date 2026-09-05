#!/usr/bin/env python3
"""Store the Xiaomiao key in macOS Keychain without echoing it."""

from __future__ import annotations

import argparse
import platform
import re
import subprocess
import sys


SERVICE = "cell-ppt-xiaomiao"
KEY_PATTERN = re.compile(r"^img_live_[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}$")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--from-stdin", action="store_true", required=True)
    args = parser.parse_args()
    del args
    if platform.system() != "Darwin":
        raise SystemExit("This helper is for macOS Keychain. Windows uses set-xiaomiao-key.ps1 and DPAPI.")
    key = sys.stdin.readline().strip()
    if not KEY_PATTERN.fullmatch(key):
        key = ""
        raise SystemExit("API key format is invalid.")
    account = subprocess.run(["id", "-un"], check=True, text=True, capture_output=True).stdout.strip()
    try:
        subprocess.run(
            ["security", "add-generic-password", "-U", "-s", SERVICE, "-a", account, "-w", key],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    finally:
        key = ""
    print("KEY_CONFIG_OK|storage=macos-keychain|plaintext_saved=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
