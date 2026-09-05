#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
manager="$script_dir/session_manager.py"
[[ "$(python3 "$manager" startup-claim)" == claimed ]] || exit 0
trap 'python3 "$manager" startup-finish' EXIT

# Config loading can launch this job before new-session creates its placeholder.
# Wait for that session explicitly instead of racing its eventual creation.
for ((attempt = 0; attempt < 100; attempt++)); do
  if tmux has-session 2>/dev/null; then
    break
  fi
  sleep 0.05
done
tmux has-session 2>/dev/null || exit 0

# Own the startup restore lifecycle so skipped restores also release numbering.
# Continuum still handles automatic saving. Reuse its multiple-server policy.
[[ ! -f "$HOME/tmux_no_auto_restore" ]] || exit 0
continuum_helpers="$HOME/.tmux/plugins/tmux-continuum/scripts/helpers.sh"
[[ -r "$continuum_helpers" ]] || exit 0
source "$continuum_helpers"
if another_tmux_server_running_on_startup; then
  exit 0
fi

restore_script="$(tmux show-option -gqv @resurrect-restore-script-path)"
[[ -n "$restore_script" && -x "$restore_script" ]] || exit 0
"$restore_script"
