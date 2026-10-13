#!/bin/bash
set -euo pipefail

label="${1:-}"
session_id="${2:-}"

if [ -z "$label" ]; then
  exit 0
fi

exec python3 "$HOME/.config/tmux/scripts/session_manager.py" rename --session "$session_id" -- "$label"
