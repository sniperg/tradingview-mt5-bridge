#!/usr/bin/env python3
"""Flask webhook receiver for TradingView -> MetaTrader 5 file bridge."""

from __future__ import annotations

import csv
import datetime as dt
import hmac
import logging
import math
import os
import sys
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any

from flask import Flask, jsonify, request
from dotenv import load_dotenv

try:
    import fcntl
except ImportError:  # pragma: no cover - non-Unix fallback
    fcntl = None


CSV_FIELDS = ["timestamp", "id", "action", "symbol", "trade_type", "lot", "sl", "tp"]
BASE_REQUIRED_FIELDS = ["secret", "action", "symbol"]
TRADE_REQUIRED_FIELDS = ["lot", "sl", "tp"]
TRADE_ACTIONS = {"buy", "sell"}
EXIT_ACTIONS = {"close_all"}
VALID_ACTIONS = TRADE_ACTIONS | EXIT_ACTIONS

load_dotenv()

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 16 * 1024
logger = logging.getLogger("tv_bridge")


class RequestError(Exception):
    """Request validation error with an HTTP status code."""

    def __init__(self, message: str, status_code: int = 400) -> None:
        super().__init__(message)
        self.status_code = status_code


def signal_file_path() -> Path:
    configured = os.environ.get("TV_BRIDGE_SIGNAL_FILE", "tv_signal.csv")
    path = Path(configured).expanduser()
    if path.is_dir():
        path = path / "tv_signal.csv"
    return path


def configure_logging() -> None:
    if logger.handlers:
        return

    logger.setLevel(logging.INFO)
    formatter = logging.Formatter(
        "%(asctime)s %(levelname)s %(message)s", datefmt="%Y-%m-%dT%H:%M:%SZ"
    )
    formatter.converter = time_gmt

    stream_handler = logging.StreamHandler(sys.stdout)
    stream_handler.setFormatter(formatter)
    logger.addHandler(stream_handler)

    log_path = signal_file_path().parent / "tv_bridge_server.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    file_handler = logging.FileHandler(log_path, encoding="utf-8")
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)


def time_gmt(*_: Any) -> tuple[int, int, int, int, int, int, int, int, int]:
    return dt.datetime.now(dt.timezone.utc).timetuple()


def redact(payload: dict[str, Any] | None) -> dict[str, Any] | None:
    if payload is None:
        return None
    redacted = dict(payload)
    if "secret" in redacted:
        redacted["secret"] = "***"
    return redacted


def parse_number(payload: dict[str, Any], field: str) -> float:
    value = payload[field]
    if isinstance(value, bool):
        raise RequestError(f"{field} must be a number")
    if isinstance(value, str) and value.strip() == "":
        raise RequestError(f"{field} is required")
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise RequestError(f"{field} must be a finite number") from exc
    if not math.isfinite(number):
        raise RequestError(f"{field} must be a finite number")
    return number


def parse_trade_type(payload: dict[str, Any]) -> str:
    if "trade_type" not in payload:
        raise RequestError("missing required field(s): trade_type")
    if not isinstance(payload["trade_type"], str):
        raise RequestError("trade_type must be a string")

    trade_type = payload["trade_type"].strip().lower()
    if not trade_type:
        raise RequestError("trade_type is required")
    if len(trade_type) > 64:
        raise RequestError("trade_type is too long")
    if not all(ch.isalnum() or ch in {"_", "-"} for ch in trade_type):
        raise RequestError("trade_type may only contain letters, numbers, underscores, or hyphens")
    return trade_type


def validate_payload(payload: Any) -> dict[str, str]:
    if not isinstance(payload, dict):
        raise RequestError("JSON object body is required")

    missing = [field for field in BASE_REQUIRED_FIELDS if field not in payload]
    if missing:
        raise RequestError(f"missing required field(s): {', '.join(missing)}")

    expected_secret = os.environ.get("TV_BRIDGE_SECRET")
    if not expected_secret:
        raise RequestError("server is missing TV_BRIDGE_SECRET", status_code=500)

    if not isinstance(payload["secret"], str):
        raise RequestError("secret must be a string")
    incoming_secret = payload["secret"]
    if not hmac.compare_digest(incoming_secret, expected_secret):
        raise RequestError("invalid secret", status_code=401)

    if not isinstance(payload["action"], str):
        raise RequestError("action must be a string")
    action = payload["action"].strip().lower()
    if action not in VALID_ACTIONS:
        raise RequestError("action must be buy, sell, or close_all")

    if not isinstance(payload["symbol"], str):
        raise RequestError("symbol must be a string")
    symbol = payload["symbol"].strip()
    if not symbol:
        raise RequestError("symbol is required")
    if any(ch in symbol for ch in [",", "\r", "\n"]):
        raise RequestError("symbol must not contain commas or newlines")
    if len(symbol) > 64:
        raise RequestError("symbol is too long")

    if action in EXIT_ACTIONS:
        timestamp = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
        signal_id = uuid.uuid4().hex
        return {
            "timestamp": timestamp,
            "id": signal_id,
            "action": action,
            "symbol": symbol,
            "trade_type": "",
            "lot": "0",
            "sl": "0",
            "tp": "0",
        }

    missing = [field for field in TRADE_REQUIRED_FIELDS if field not in payload]
    if missing:
        raise RequestError(f"missing required field(s): {', '.join(missing)}")

    trade_type = parse_trade_type(payload)

    lot = parse_number(payload, "lot")
    if lot <= 0:
        raise RequestError("lot must be greater than zero")

    sl = parse_number(payload, "sl")
    tp = parse_number(payload, "tp")
    if sl <= 0 or tp <= 0:
        raise RequestError("sl and tp must be greater than zero")
    if action == "buy" and sl >= tp:
        raise RequestError("buy signals require sl < tp")
    if action == "sell" and tp >= sl:
        raise RequestError("sell signals require tp < sl")

    timestamp = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    signal_id = uuid.uuid4().hex

    return {
        "timestamp": timestamp,
        "id": signal_id,
        "action": action,
        "symbol": symbol,
        "trade_type": trade_type,
        "lot": format_decimal(lot),
        "sl": format_decimal(sl),
        "tp": format_decimal(tp),
    }


def format_decimal(value: float) -> str:
    return format(value, ".15g")


@contextmanager
def exclusive_file_lock(path: Path):
    lock_path = path.with_name(path.name + ".lock")
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("w", encoding="utf-8") as lock_file:
        if fcntl is not None:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            if fcntl is not None:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


def append_signal(row: dict[str, str]) -> Path:
    path = signal_file_path()
    path.parent.mkdir(parents=True, exist_ok=True)

    with exclusive_file_lock(path):
        needs_header = not path.exists() or path.stat().st_size == 0
        with path.open("a", newline="", encoding="utf-8") as csv_file:
            writer = csv.DictWriter(csv_file, fieldnames=CSV_FIELDS)
            if needs_header:
                writer.writeheader()
            writer.writerow(row)
            csv_file.flush()
            os.fsync(csv_file.fileno())

    return path


@app.post("/webhook")
def webhook():
    payload = request.get_json(silent=True)
    logger.info("received alert from %s payload=%s", request.remote_addr, redact(payload))

    try:
        row = validate_payload(payload)
        output_path = append_signal(row)
    except RequestError as exc:
        logger.warning("rejected alert status=%s reason=%s", exc.status_code, exc)
        return jsonify({"ok": False, "error": str(exc)}), exc.status_code
    except Exception:
        logger.exception("failed to write signal")
        return jsonify({"ok": False, "error": "internal server error"}), 500

    logger.info("accepted alert id=%s file=%s", row["id"], output_path)
    return jsonify({"ok": True, "id": row["id"]})


@app.get("/health")
def health():
    return jsonify({"ok": True})


def main() -> int:
    configure_logging()
    if not os.environ.get("TV_BRIDGE_SECRET"):
        logger.error("TV_BRIDGE_SECRET is not set")
        return 2

    host = os.environ.get("TV_BRIDGE_HOST", "127.0.0.1")
    port = int(os.environ.get("TV_BRIDGE_PORT", "5055"))
    logger.info("starting webhook server host=%s port=%s", host, port)
    logger.info("writing signals to %s", signal_file_path())
    app.run(host=host, port=port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
