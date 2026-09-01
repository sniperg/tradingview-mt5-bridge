#!/usr/bin/env bash
set -u

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$PROJECT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_DIR/.env"
  set +a
fi

PORT="${TV_BRIDGE_PORT:-5055}"
LOCAL_URL="http://127.0.0.1:${PORT}/health"
failures=0

if curl -fsS --max-time 5 "$LOCAL_URL" >/dev/null; then
  echo "OK   bridge health endpoint: $LOCAL_URL"
else
  echo "FAIL bridge health endpoint: $LOCAL_URL"
  failures=$((failures + 1))
fi

if [[ -n "${TV_BRIDGE_SIGNAL_FILE:-}" ]]; then
  SIGNAL_DIR="$(dirname "$TV_BRIDGE_SIGNAL_FILE")"
  if [[ -d "$SIGNAL_DIR" && -w "$SIGNAL_DIR" ]]; then
    echo "OK   signal directory is writable"
  else
    echo "FAIL signal directory is missing or not writable"
    failures=$((failures + 1))
  fi
else
  echo "FAIL TV_BRIDGE_SIGNAL_FILE is not configured"
  failures=$((failures + 1))
fi

if [[ -n "${TV_BRIDGE_PUBLIC_URL:-}" ]]; then
  status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$TV_BRIDGE_PUBLIC_URL" || true)"
  if [[ "$status" == "405" ]]; then
    echo "OK   public webhook route is reachable"
  else
    echo "WARN public webhook returned HTTP ${status:-no response}"
  fi
fi

exit "$failures"
