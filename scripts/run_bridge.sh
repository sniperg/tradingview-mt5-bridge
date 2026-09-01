#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="$PROJECT_DIR/.venv/bin/python"

if [[ ! -x "$PYTHON" ]]; then
  echo "Virtual environment not found. Run scripts/setup.sh first." >&2
  exit 1
fi

cd "$PROJECT_DIR"
exec "$PYTHON" webhook_server.py
