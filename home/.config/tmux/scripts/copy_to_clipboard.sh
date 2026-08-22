#!/usr/bin/env bash
set -euo pipefail

content=$(cat | tr -d '\r')
# Update tmux buffer and system clipboard (uses tmux set-clipboard setting)
tmux set-buffer -w -- "$content"
printf '%s' "$content" | pbcopy || true
