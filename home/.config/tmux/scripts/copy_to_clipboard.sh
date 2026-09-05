#!/usr/bin/env bash
set -euo pipefail

copy_file="$(mktemp "${TMPDIR:-/tmp}/tmux-copy.XXXXXX")"
trap 'rm -f -- "$copy_file"' EXIT
cat > "$copy_file"
# Keep trailing newlines and avoid the command-line argument size limit.
tmux load-buffer -w "$copy_file"
pbcopy < "$copy_file" || true
