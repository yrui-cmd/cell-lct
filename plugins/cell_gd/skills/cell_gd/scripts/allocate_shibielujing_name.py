from __future__ import annotations

import argparse
import re
from pathlib import Path


NAME_RE = re.compile(r"^shibielujing(\d+)(?:\.|$)", re.IGNORECASE)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()

    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    used: set[int] = set()
    for path in root.rglob("*"):
        match = NAME_RE.match(path.name)
        if match:
            used.add(int(match.group(1)))

    next_number = max(used, default=0) + 1
    print(f"shibielujing{next_number}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
