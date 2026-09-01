#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$PROJECT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_DIR/.env"
  set +a
fi

PORT="${TV_BRIDGE_PORT:-5055}"
if [[ -n "${TV_BRIDGE_NGROK_DOMAIN:-}" ]]; then
  exec ngrok http "$PORT" --url "$TV_BRIDGE_NGROK_DOMAIN"
fi

exec ngrok http "$PORT"
