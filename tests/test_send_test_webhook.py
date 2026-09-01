import json
import sys

import send_test_webhook


def test_print_json_uses_env_secret(monkeypatch, capsys):
    monkeypatch.setenv("TV_BRIDGE_SECRET", "test-only-secret")
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "send_test_webhook.py",
            "--print-json",
            "--action",
            "buy",
            "--symbol",
            "EURUSD",
            "--trade-type",
            "breakout",
            "--lot",
            "0.01",
            "--sl",
            "1.08",
            "--tp",
            "1.09",
        ],
    )

    assert send_test_webhook.main() == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload == {
        "secret": "test-only-secret",
        "action": "buy",
        "symbol": "EURUSD",
        "trade_type": "breakout",
        "lot": 0.01,
        "sl": 1.08,
        "tp": 1.09,
    }


def test_print_close_all_contains_only_required_fields(monkeypatch, capsys):
    monkeypatch.setenv("TV_BRIDGE_SECRET", "test-only-secret")
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "send_test_webhook.py",
            "--print-json",
            "--action",
            "close_all",
            "--symbol",
            "EURUSD",
        ],
    )

    assert send_test_webhook.main() == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload == {
        "secret": "test-only-secret",
        "action": "close_all",
        "symbol": "EURUSD",
    }
