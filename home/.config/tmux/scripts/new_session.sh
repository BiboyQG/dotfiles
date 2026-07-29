#!/bin/bash

session_id=$(tmux new-session -d -P -F '#{session_id}' 2>/dev/null)

if [ -z "$session_id" ]; then
  exit 0
fi

tmux switch-client -t "$session_id"
