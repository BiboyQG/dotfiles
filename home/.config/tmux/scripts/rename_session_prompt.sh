#!/bin/bash
set -euo pipefail

label="${1:-}"
session_id="${2:-}"
# The prompt captures a numeric ID before its template is parsed again.
[[ "$session_id" =~ ^[0-9]+$ ]] && session_id="\$$session_id"

if [ -z "$label" ]; then
  exit 0
fi

exec python3 "$HOME/.config/tmux/scripts/session_manager.py" rename --session "$session_id" -- "$label"
