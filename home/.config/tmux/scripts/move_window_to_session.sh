#!/bin/bash
set -euo pipefail

index="${1:-}"
session_id="${2:-}"
window_id="${3:-}"
client="${4:-}"

if [[ -z "$index" || ! "$index" =~ ^[0-9]+$ ]]; then
  exit 0
fi

exec python3 "$HOME/.config/tmux/scripts/session_manager.py" move-window-to "$index" \
  --session "$session_id" --window "$window_id" --client "$client"
