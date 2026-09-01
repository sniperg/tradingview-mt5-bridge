# TradingView to MetaTrader 5 Bridge

A small self-hosted bridge that receives TradingView webhook alerts and executes them through a MetaTrader 5 Expert Advisor (EA).

TradingView sends JSON to a local Flask server through an HTTPS tunnel. The server validates a shared secret and appends the signal to MT5's shared `Common/Files/tv_signal.csv`. The EA polls that file, ignores duplicate signal IDs, validates the order against the broker's symbol rules, and submits the trade.

> Automated trading can lose money. Test this bridge on a demo account first. You are responsible for alert logic, position sizing, broker compatibility, tunnel security, and every order sent through your account.

## Included files

- `webhook_server.py` — validates webhooks and writes the MT5 signal file.
- `TradingViewBridgeEA.mq5` — reads signals and manages MT5 orders.
- `send_test_webhook.py` — sends local test signals without TradingView.
- `.env.example` — configuration template with no real credentials.
- `scripts/` — setup, startup, tunnel, and health-check helpers for macOS/Linux.
- `examples/` — sample TradingView alert bodies.
- `tests/` — server validation and file-handoff tests.

For the exact webhook field reference and ready-to-paste notification bodies, see [Alert message format](docs/ALERT_FORMAT.md).

## Requirements

- Python 3.10 or newer
- MetaTrader 5 with algorithmic trading enabled
- A TradingView plan that supports webhook alerts
- A public HTTPS tunnel such as ngrok or Cloudflare Tunnel

The shell helpers target macOS/Linux. The Python server and EA can also be used on Windows by running the equivalent commands manually.

## 1. Download and install the server

The repository owner must make the repository public or grant your GitHub account access before you can download it.

With Git installed:

```bash
git clone https://github.com/sniperg/tradingview-mt5-bridge.git
cd tradingview-mt5-bridge
chmod +x scripts/*.sh
./scripts/setup.sh
```

Without Git, use GitHub's **Code → Download ZIP**, extract the archive, open a terminal in the extracted folder, and run:

```bash
chmod +x scripts/*.sh
./scripts/setup.sh
```

Setup installs the Python dependencies, creates `.env`, and generates a fresh random bridge secret. If setup asks for the signal-file path and you do not know it yet, press Enter and complete the next section before editing `.env`.

### The keys and credentials are different

- **Bridge secret (`TV_BRIDGE_SECRET`)** — generated locally in `.env`. The server and every TradingView alert must use the exact same value. It is case-sensitive. This is the only credential inside the alert message.
- **Tunnel credential** — for example, an ngrok authtoken. Configure it with the tunnel provider's own login command. Never put it in `.env` as `TV_BRIDGE_SECRET` and never send it in a TradingView alert.
- **MT5 login** — stays inside MetaTrader 5. The bridge source, Flask server, and TradingView message do not need the MT5 account password.
- **GitHub login** — needed only to download a private repository; it has no role in trading.

Never commit `.env` or paste its secret into an issue, screenshot, chat, or public example. If the bridge secret is exposed, generate a replacement, update `.env`, restart the server, and update every TradingView alert.

## 2. Find the MT5 shared files folder

In MetaTrader 5, choose **File → Open Data Folder**. The opened directory is normally one terminal instance below the `Terminal` directory. Go up to `Terminal`, then open `Common/Files`. Set `TV_BRIDGE_SIGNAL_FILE` in `.env` to the full path of a file named `tv_signal.csv` inside that folder.

Typical paths vary by operating system, broker build, and macOS Wine wrapper. Do not copy another person's absolute path.

The finished `.env` must contain real values in this shape:

```dotenv
TV_BRIDGE_SECRET=your_generated_value
TV_BRIDGE_SIGNAL_FILE="/your/real/path/MetaQuotes/Terminal/Common/Files/tv_signal.csv"
TV_BRIDGE_HOST=127.0.0.1
TV_BRIDGE_PORT=5055
```

Do not put spaces around `=`. Keep paths with spaces inside double quotes.

## 3. Install the Expert Advisor

1. In MT5, choose **File → Open Data Folder**.
2. Copy `TradingViewBridgeEA.mq5` into `MQL5/Experts/`.
3. Open the file in MetaEditor and compile it.
4. Attach `TradingViewBridgeEA` to a chart.
5. Enable **Algo Trading** and allow automated trading for the EA.

The defaults poll once per second and use magic number `20260623`. Change the magic number if it conflicts with another EA. With `ProcessExistingSignalsOnStart=false`, pre-existing rows are marked as processed instead of traded when the EA starts.

## 4. Start and test locally

Start the bridge:

```bash
./scripts/run_bridge.sh
```

In another terminal, send a test using current market-appropriate stop-loss and take-profit prices:

```bash
.venv/bin/python send_test_webhook.py \
  --action buy \
  --symbol EURUSD \
  --trade-type breakout \
  --lot 0.01 \
  --sl 1.0800 \
  --tp 1.0900
```

The server accepting a signal only confirms the file handoff. Confirm the EA result in MT5's **Experts** tab and `Common/Files/tv_bridge_ea.log`.

Run the local health check with:

```bash
./scripts/check_bridge_status.sh
```

## 5. Expose the webhook

Install and authenticate your tunnel provider. For ngrok:

```bash
./scripts/run_ngrok.sh
```

Use the generated HTTPS URL followed by `/webhook` as the TradingView webhook URL:

```text
https://your-random-domain.example/webhook
```

Keep the Flask server bound to `127.0.0.1`; let the tunnel provide public HTTPS. Free tunnel URLs may change after restart. A reserved ngrok domain can be set through `TV_BRIDGE_NGROK_DOMAIN`.

## 6. Create TradingView alerts

1. Open the desired chart and create an alert.
2. Choose the condition that should trigger the trade.
3. Enable the **Webhook URL** notification.
4. Paste the public HTTPS tunnel URL ending in `/webhook`.
5. Paste a valid JSON object into the alert's **Message** field.
6. Verify the broker symbol, lot size, and absolute SL/TP prices.
7. Create the alert and trigger it on a demo account first.

The webhook method is `POST` and the message must be JSON. The server rejects bodies larger than 16 KiB. Replace the example secret with the exact value after `TV_BRIDGE_SECRET=` in `.env`; do not include `.env` quote characters in the JSON value.

To avoid typing mistakes, print a complete ready-to-paste buy message using the secret already stored in `.env`:

```bash
.venv/bin/python send_test_webhook.py \
  --print-json \
  --action buy \
  --symbol EURUSD \
  --trade-type breakout \
  --lot 0.01 \
  --sl 1.0800 \
  --tp 1.0900
```

This command displays the secret in the terminal output. Paste the result only into your private TradingView alert message and then clear the terminal if necessary.

Buy or sell signals require:

- `secret`: exact shared secret
- `action`: `buy` or `sell`
- `symbol`: the broker's exact MT5 symbol, including any suffix
- `trade_type`: a short label containing letters, numbers, `_`, or `-`
- `lot`: positive order volume
- `sl` and `tp`: absolute prices, not distances

Example:

```json
{
  "secret": "REPLACE_WITH_YOUR_SECRET",
  "action": "buy",
  "symbol": "EURUSD",
  "trade_type": "breakout",
  "lot": 0.01,
  "sl": 1.0800,
  "tp": 1.0900
}
```

Close every position opened by this bridge for one symbol and magic number:

```json
{
  "secret": "REPLACE_WITH_YOUR_SECRET",
  "action": "close_all",
  "symbol": "EURUSD"
}
```

The EA will reject invalid symbol names, volumes outside broker limits, stops on the wrong side of the market, and stops closer than the broker permits.

For buys, use `SL < current ask < TP`. For sells, use `TP < current bid < SL`. The example prices are illustrations and will usually be wrong for the current market. The symbol must exactly match MT5, including broker suffixes such as `.a`, `m`, or `_pro`; TradingView's ticker name may not be identical.

See [Alert message format](docs/ALERT_FORMAT.md) for the complete field table, sell payload, close behavior, HTTP responses, and dynamic-alert guidance.

## Normal daily startup

Every time the computer or tunnel restarts:

1. Open MT5, log in, attach the EA, and enable Algo Trading.
2. Run `./scripts/run_bridge.sh` and keep it running.
3. Run `./scripts/run_ngrok.sh` in a second terminal and keep it running.
4. If the tunnel URL changed, update the Webhook URL in every TradingView alert.
5. Run `./scripts/check_bridge_status.sh`.

The bridge is ready only when the Flask server, HTTPS tunnel, MT5 terminal, and EA are all running.

## Tests

```bash
.venv/bin/python -m pip install -r requirements-dev.txt
.venv/bin/python -m pytest
```

Tests exercise webhook validation and CSV handoff only; they never connect to MT5 or place trades.

## Troubleshooting

- **401 invalid secret** — the JSON `secret` does not exactly match `TV_BRIDGE_SECRET`.
- **Server accepts but no trade appears** — verify the exact broker symbol, Algo Trading, EA attachment, and MT5 Experts log.
- **Signal file not found** — correct `TV_BRIDGE_SIGNAL_FILE`; it must point into MT5's terminal-wide `Common/Files` folder.
- **Invalid stops or volume** — use current market prices and values permitted by the broker.
- **TradingView cannot connect** — verify the HTTPS tunnel is running and the URL ends with `/webhook`.

## Security notes

- Use a new random secret for every installation.
- Do not expose Flask directly to the internet or bind it to `0.0.0.0` unless you understand the network risk.
- Restrict the tunnel and rotate the secret if it is ever disclosed.
- Keep `.env`, runtime logs, CSV files, compiled EAs, and MT5 account data out of Git.
- Review the source and test on demo before allowing live orders.
