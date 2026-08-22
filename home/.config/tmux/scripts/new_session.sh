#!/bin/bash
set -euo pipefail

client="${1:-}"

session_id="$(tmux new-session -d -P -F '#{session_id}' 2>/dev/null)" || exit 0
[[ -n "$session_id" ]] || exit 0

if [[ -n "$client" ]]; then
  tmux switch-client -c "$client" -t "$session_id"
else
  tmux switch-client -t "$session_id"
fi
