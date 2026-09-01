# TradingView alert message format

This document defines the exact notification body accepted by `POST /webhook`. Paste one JSON object into TradingView's alert **Message** field. JSON does not allow comments, trailing commas, or unquoted text.

## Endpoint

```text
POST https://YOUR-TUNNEL-DOMAIN/webhook
Content-Type: application/json
```

The URL must end with `/webhook`. `/health` is only for health checks and does not accept trades.

## Credentials

The JSON `secret` is the value of `TV_BRIDGE_SECRET` in `.env`.

```dotenv
TV_BRIDGE_SECRET=example-value-generated-on-your-computer
```

The alert uses only the value after `=`:

```json
"secret": "example-value-generated-on-your-computer"
```

Do not use an ngrok authtoken, GitHub token, broker password, or somebody else's bridge secret. The setup script generates a unique secret locally. Anyone who knows it can submit signals while the webhook is reachable, so keep the alert and `.env` private.

## Buy and sell fields

| Field | JSON type | Required | Rules |
| --- | --- | --- | --- |
| `secret` | string | Yes | Exact, case-sensitive match with `TV_BRIDGE_SECRET`. |
| `action` | string | Yes | `buy` or `sell`. Lowercase is recommended. |
| `symbol` | string | Yes | Exact MT5 broker symbol, including any suffix; maximum 64 characters. |
| `trade_type` | string | Yes | Strategy/entry label used in the MT5 position comment; letters, numbers, `_`, and `-` only; maximum 64 characters. |
| `lot` | number | Yes | Greater than zero and within the broker's minimum/maximum volume. |
| `sl` | number | Yes | Absolute stop-loss price, greater than zero. |
| `tp` | number | Yes | Absolute take-profit price, greater than zero. |

Price relationships:

- Buy: `SL < current ask < TP`
- Sell: `TP < current bid < SL`

The MT5 EA also enforces the broker's minimum stop distance. A message can be accepted by the server but still rejected by the EA if market prices moved or broker rules are not met.

### Buy example

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

### Sell example

```json
{
  "secret": "REPLACE_WITH_YOUR_SECRET",
  "action": "sell",
  "symbol": "EURUSD",
  "trade_type": "breakout",
  "lot": 0.01,
  "sl": 1.0900,
  "tp": 1.0800
}
```

These prices are examples, not live trade recommendations. Replace them with values appropriate at the moment the alert fires.

## Close-all fields

`close_all` closes positions only when both of these match:

- The exact `symbol` in the message
- The EA's configured `MagicNumber`

It does not close manual positions or positions opened by another magic number.

| Field | JSON type | Required | Rules |
| --- | --- | --- | --- |
| `secret` | string | Yes | Exact shared secret. |
| `action` | string | Yes | Must be `close_all`. |
| `symbol` | string | Yes | Exact MT5 broker symbol. |

```json
{
  "secret": "REPLACE_WITH_YOUR_SECRET",
  "action": "close_all",
  "symbol": "EURUSD"
}
```

`lot`, `sl`, `tp`, and `trade_type` are not required for `close_all`.

## Generate a message instead of typing it

The helper reads the private secret from `.env` and prints valid JSON:

```bash
.venv/bin/python send_test_webhook.py \
  --print-json \
  --action sell \
  --symbol EURUSD \
  --trade-type breakout \
  --lot 0.01 \
  --sl 1.0900 \
  --tp 1.0800
```

For a close message:

```bash
.venv/bin/python send_test_webhook.py \
  --print-json \
  --action close_all \
  --symbol EURUSD
```

The output contains the real secret. Do not post it publicly.

## Static and dynamic alerts

A static alert contains fixed values like the examples above. It is the easiest format to test.

A dynamic alert may use values produced by a TradingView strategy or indicator. The final message delivered to the server must still be valid JSON with all required fields. In particular:

- String results must remain inside JSON quotes.
- Numeric `lot`, `sl`, and `tp` results should resolve to finite numbers.
- The resolved symbol must exactly match the broker's MT5 symbol. Hardcoding the MT5 symbol is safer when TradingView and broker names differ.
- Never publish Pine source containing a real bridge secret.

Before enabling a live alert, inspect or log one resolved message and test the same values locally with `send_test_webhook.py` on a demo account.

## Server responses

| HTTP status | Meaning |
| --- | --- |
| `200` | Signal was validated and written to the CSV handoff. This does not guarantee MT5 executed it. |
| `400` | Missing field, invalid action/type/value, invalid JSON, or invalid SL/TP relationship. |
| `401` | Secret does not match. |
| `413` | Message is larger than 16 KiB. |
| `500` | Server configuration or signal-file write failure. |

A successful response looks like:

```json
{
  "id": "generated-signal-id",
  "ok": true
}
```

Each accepted signal receives a unique ID. The EA stores processed IDs so polling or restarting does not repeat the same row.

## Pre-live checklist

- The local `/health` check passes.
- The HTTPS tunnel points to local port `5055`.
- The alert URL ends in `/webhook`.
- The alert secret exactly matches `.env`.
- The MT5 symbol, lot, SL, and TP are valid for the broker.
- MT5 is logged into a demo account, Algo Trading is enabled, and the EA is attached.
- One local buy/sell test and one `close_all` test have been confirmed in the MT5 Experts log.
