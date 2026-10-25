#!/usr/bin/env bash
set -euo pipefail

current_session_id="$1"
term_width="$2"

inactive_bg="#373b41"
inactive_fg="#c5c8c6"
active_bg="#b294bb"
active_fg="#1d1f21"
separator=""
left_cap="█"
max_width=18

is_narrow=0
(( term_width < 80 )) && is_narrow=1

# One tmux client: hold the session-manager lock while listing so a rename in
# progress cannot leak its temporary names into the bar.
sessions=$(tmux wait-for -L dotfiles-session-manager \; \
  list-sessions -F $'#{session_id}\t#{session_name}\t#{session_created}' \; \
  wait-for -U dotfiles-session-manager 2>/dev/null || true)
if [[ -z "$sessions" ]]; then
  exit 0
fi

# Order as session_manager.py does: indexed sessions by index, then the rest
# by creation time. Indexes stay far below 10^10, so one numeric key serves.
entries=()
while IFS=$'\t' read -r session_id name created; do
  if [[ "$name" =~ ^([0-9]+)- ]]; then
    key=$(( 10#${BASH_REMATCH[1]} ))
  else
    key=$(( created + 10000000000 ))
  fi
  entries+=("${key}"$'\t'"${session_id}"$'\t'"${name}")
done <<< "$sessions"

sorted=()
for entry in "${entries[@]}"; do
  key="${entry%%$'\t'*}"
  i=${#sorted[@]}
  while (( i > 0 )) && (( ${sorted[i-1]%%$'\t'*} > key )); do
    sorted[i]="${sorted[i-1]}"
    i=$(( i - 1 ))
  done
  sorted[i]="$entry"
done

rendered=""
prev_bg=""
for entry in "${sorted[@]}"; do
  rest="${entry#*$'\t'}"
  session_id="${rest%%$'\t'*}"
  name="${rest#*$'\t'}"

  segment_bg="$inactive_bg"
  segment_fg="$inactive_fg"
  index=""
  trimmed_name="$name"
  if [[ "$name" =~ ^([0-9]+)-(.*)$ ]]; then
    index="${BASH_REMATCH[1]}"
    trimmed_name="${BASH_REMATCH[2]}"
  fi
  is_current=0
  if [[ "$session_id" == "$current_session_id" ]]; then
    is_current=1
    segment_bg="$active_bg"
    segment_fg="$active_fg"
  fi

  if (( is_narrow == 1 && is_current == 0 )) && [[ -n "$index" ]]; then
    label="$index"         # narrow: inactive sessions show their slot number
  else
    label="$trimmed_name"  # active or wide: the title without its N- prefix
  fi
  if (( ${#label} > max_width )); then
    label="${label:0:max_width-1}…"
  fi
  # tmux re-parses this job's output as a format string; a literal '#' is '##'.
  label="${label//#/##}"

  if [[ -z "$prev_bg" ]]; then
    rendered+="#[fg=${segment_bg},bg=default]${left_cap}"
  else
    rendered+="#[fg=${prev_bg},bg=${segment_bg}]${separator}"
  fi
  rendered+="#[fg=${segment_fg},bg=${segment_bg}] ${label} "
  prev_bg="$segment_bg"
done

rendered+="#[fg=${prev_bg},bg=default]${separator}"

printf '%s' "$rendered"
