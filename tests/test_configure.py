import sys

from dotenv import dotenv_values

from scripts import configure


def test_creates_private_env_with_generated_secret(tmp_path, monkeypatch):
    env_path = tmp_path / ".env"
    monkeypatch.setattr(configure, "ENV_PATH", env_path)
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "configure.py",
            "--signal-file",
            "/tmp/MT5 Common/Files/tv_signal.csv",
        ],
    )

    assert configure.main() == 0
    values = dotenv_values(env_path)

    assert values["TV_BRIDGE_SECRET"] != "REPLACE_WITH_A_LONG_RANDOM_SECRET"
    assert len(values["TV_BRIDGE_SECRET"]) >= 32
    assert values["TV_BRIDGE_SIGNAL_FILE"] == "/tmp/MT5 Common/Files/tv_signal.csv"
    assert env_path.stat().st_mode & 0o777 == 0o600


def test_existing_env_is_not_overwritten(tmp_path, monkeypatch):
    env_path = tmp_path / ".env"
    env_path.write_text("TV_BRIDGE_SECRET=keep-me\n", encoding="utf-8")
    monkeypatch.setattr(configure, "ENV_PATH", env_path)
    monkeypatch.setattr(sys, "argv", ["configure.py"])

    assert configure.main() == 0
    assert env_path.read_text(encoding="utf-8") == "TV_BRIDGE_SECRET=keep-me\n"
