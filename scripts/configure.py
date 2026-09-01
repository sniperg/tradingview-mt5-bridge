#!/usr/bin/env python3
"""Create a private .env with a fresh bridge secret."""

from __future__ import annotations

import argparse
import secrets
import stat
import sys
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parents[1]
ENV_PATH = PROJECT_DIR / ".env"
TEMPLATE_PATH = PROJECT_DIR / ".env.example"
SIGNAL_PLACEHOLDER = "/absolute/path/to/MetaQuotes/Terminal/Common/Files/tv_signal.csv"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create .env with a fresh webhook secret. Existing files are preserved."
    )
    parser.add_argument(
        "--signal-file",
        help="Full path to MetaTrader 5 Common/Files/tv_signal.csv.",
    )
    return parser.parse_args()


def quote_dotenv(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def main() -> int:
    args = parse_args()
    if ENV_PATH.exists():
        print(f"{ENV_PATH} already exists; left it unchanged.")
        return 0

    signal_file = args.signal_file
    if signal_file is None and sys.stdin.isatty():
        print("Enter the full path to MT5 Common/Files/tv_signal.csv.")
        print("Press Enter if you do not know it yet; you can edit .env later.")
        signal_file = input("Signal file path: ").strip()
    signal_file = signal_file or SIGNAL_PLACEHOLDER

    template = TEMPLATE_PATH.read_text(encoding="utf-8")
    template = template.replace(
        "TV_BRIDGE_SECRET=REPLACE_WITH_A_LONG_RANDOM_SECRET",
        f"TV_BRIDGE_SECRET={secrets.token_urlsafe(32)}",
    )
    template = template.replace(
        f'TV_BRIDGE_SIGNAL_FILE="{SIGNAL_PLACEHOLDER}"',
        f"TV_BRIDGE_SIGNAL_FILE={quote_dotenv(signal_file)}",
    )
    ENV_PATH.write_text(template, encoding="utf-8")
    ENV_PATH.chmod(stat.S_IRUSR | stat.S_IWUSR)

    print(f"Created private configuration: {ENV_PATH}")
    print("A fresh bridge secret was generated and was not printed.")
    if signal_file == SIGNAL_PLACEHOLDER:
        print("NEXT: replace TV_BRIDGE_SIGNAL_FILE in .env before starting the bridge.")
    else:
        print("Configuration is ready. Continue with the MT5 EA installation.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
