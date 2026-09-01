#!/usr/bin/env python3
"""Send a local test signal to the TradingView bridge webhook."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

from dotenv import load_dotenv


load_dotenv()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send a test TradingView-style webhook to the local bridge server."
    )
    parser.add_argument("--url", default="http://127.0.0.1:5055/webhook")
    parser.add_argument("--action", required=True, choices=["buy", "sell", "close_all"])
    parser.add_argument("--symbol", required=True)
    parser.add_argument("--trade-type", default="buybreakout")
    parser.add_argument("--lot", type=float)
    parser.add_argument("--sl", type=float)
    parser.add_argument("--tp", type=float)
    parser.add_argument(
        "--secret",
        default=os.environ.get("TV_BRIDGE_SECRET"),
        help="Webhook secret. Defaults to TV_BRIDGE_SECRET.",
    )
    parser.add_argument(
        "--print-json",
        action="store_true",
        help="Print a ready-to-paste TradingView JSON message instead of sending it.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.secret:
        print("TV_BRIDGE_SECRET is not set. Export it or pass --secret.", file=sys.stderr)
        return 2

    if args.action in {"buy", "sell"} and (
        args.lot is None or args.sl is None or args.tp is None
    ):
        print("buy/sell tests require --lot, --sl, and --tp.", file=sys.stderr)
        return 2

    payload = {
        "secret": args.secret,
        "action": args.action,
        "symbol": args.symbol,
    }
    if args.action != "close_all":
        payload.update(
            {"trade_type": args.trade_type, "lot": args.lot, "sl": args.sl, "tp": args.tp}
        )

    if args.print_json:
        print(json.dumps(payload, indent=2))
        return 0

    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        args.url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            response_body = response.read().decode("utf-8")
            print(f"status={response.status}")
            print(response_body)
            return 0 if 200 <= response.status < 300 else 1
    except urllib.error.HTTPError as exc:
        response_body = exc.read().decode("utf-8", errors="replace")
        print(f"status={exc.code}", file=sys.stderr)
        print(response_body, file=sys.stderr)
        return 1
    except urllib.error.URLError as exc:
        print(f"request failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
