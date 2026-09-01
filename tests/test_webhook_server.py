import csv

import pytest

import webhook_server


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("TV_BRIDGE_SECRET", "test-only-secret")
    monkeypatch.setenv("TV_BRIDGE_SIGNAL_FILE", str(tmp_path / "tv_signal.csv"))
    webhook_server.app.config.update(TESTING=True)
    return webhook_server.app.test_client()


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"ok": True}


def test_rejects_invalid_secret(client):
    response = client.post(
        "/webhook",
        json={
            "secret": "wrong",
            "action": "buy",
            "symbol": "EURUSD",
            "trade_type": "breakout",
            "lot": 0.01,
            "sl": 1.08,
            "tp": 1.09,
        },
    )
    assert response.status_code == 401
    assert response.get_json()["ok"] is False


def test_buy_signal_is_written_without_secret(client, tmp_path):
    response = client.post(
        "/webhook",
        json={
            "secret": "test-only-secret",
            "action": "buy",
            "symbol": "EURUSD",
            "trade_type": "breakout",
            "lot": 0.01,
            "sl": 1.08,
            "tp": 1.09,
        },
    )
    assert response.status_code == 200
    assert set(response.get_json()) == {"ok", "id"}

    with (tmp_path / "tv_signal.csv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))

    assert len(rows) == 1
    assert rows[0]["action"] == "buy"
    assert rows[0]["symbol"] == "EURUSD"
    assert rows[0]["trade_type"] == "breakout"
    assert "secret" not in rows[0]


def test_close_all_signal(client, tmp_path):
    response = client.post(
        "/webhook",
        json={
            "secret": "test-only-secret",
            "action": "close_all",
            "symbol": "EURUSD",
        },
    )
    assert response.status_code == 200

    with (tmp_path / "tv_signal.csv").open(newline="", encoding="utf-8") as handle:
        row = next(csv.DictReader(handle))

    assert row["action"] == "close_all"
    assert row["lot"] == "0"


def test_rejects_invalid_buy_stops(client):
    response = client.post(
        "/webhook",
        json={
            "secret": "test-only-secret",
            "action": "buy",
            "symbol": "EURUSD",
            "trade_type": "breakout",
            "lot": 0.01,
            "sl": 1.10,
            "tp": 1.09,
        },
    )
    assert response.status_code == 400
