#!/usr/bin/env zsh
set -euo pipefail

ROOT="${0:A:h}"
cd "$ROOT"

log() {
  printf "==> %s\n" "$*"
}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    printf "Missing checker dependency: %s\n" "$1" >&2
    exit 1
  }
}

for command in bash git jq luac make plutil python3 ruby stow zsh; do
  require "$command"
done

log "Checking shell syntax"
zsh -n setup.sh .zshrc .config/aerospace/scripts/resize-edge .config/sketchybar/scripts/ai_usage.sh
bash -n \
  bin/abs \
  bin/ip \
  .config/tmux/scripts/copy_to_clipboard.sh \
  .config/tmux/scripts/move_window_to_session.sh \
  .config/tmux/scripts/new_session.sh \
  .config/tmux/scripts/rename_session_prompt.sh \
  .config/tmux/scripts/session_created.sh \
  .config/tmux/tmux-status/left.sh

log "Checking Lua syntax"
while IFS= read -r file; do
  [[ -f "$file" ]] && luac -p "$file"
done < <(git ls-files '*.lua')

log "Checking Python syntax"
python3 - "$ROOT" <<'PY'
import ast
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
files = subprocess.check_output(
    ["git", "ls-files", "*.py"], cwd=root, text=True
).splitlines()
for name in files:
    path = root / name
    if path.is_file():
        ast.parse(path.read_text(), filename=name)
PY

log "Checking TOML"
python3 - "$ROOT" <<'PY'
import subprocess
import sys
import tomllib
from pathlib import Path

root = Path(sys.argv[1])
files = subprocess.check_output(
    ["git", "ls-files", "*.toml"], cwd=root, text=True
).splitlines()
for name in files:
    path = root / name
    if path.is_file():
        with path.open("rb") as handle:
            tomllib.load(handle)
PY

log "Checking JSON and JSONC"
jq empty .config/nvim/lazyvim.json
python3 - "$ROOT" <<'PY'
import json
import subprocess
import sys
from pathlib import Path


def strip_comments(text: str) -> str:
    output = []
    index = 0
    in_string = False
    escaped = False
    while index < len(text):
        char = text[index]
        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue

        if char == '"':
            in_string = True
            output.append(char)
            index += 1
            continue

        next_char = text[index + 1] if index + 1 < len(text) else ""
        if char == "/" and next_char == "/":
            index += 2
            while index < len(text) and text[index] not in "\r\n":
                index += 1
            continue
        if char == "/" and next_char == "*":
            index += 2
            while index + 1 < len(text) and text[index : index + 2] != "*/":
                if text[index] in "\r\n":
                    output.append(text[index])
                index += 1
            if index + 1 >= len(text):
                raise ValueError("unterminated block comment")
            index += 2
            continue

        output.append(char)
        index += 1
    return "".join(output)


def strip_trailing_commas(text: str) -> str:
    output = []
    index = 0
    in_string = False
    escaped = False
    while index < len(text):
        char = text[index]
        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue

        if char == '"':
            in_string = True
        elif char == ",":
            lookahead = index + 1
            while lookahead < len(text) and text[lookahead].isspace():
                lookahead += 1
            if lookahead < len(text) and text[lookahead] in "]}":
                index += 1
                continue

        output.append(char)
        index += 1
    return "".join(output)


root = Path(sys.argv[1])
files = subprocess.check_output(
    ["git", "ls-files", "*.json", "*.jsonc"], cwd=root, text=True
).splitlines()
for name in files:
    path = root / name
    if path.is_file():
        json.loads(strip_trailing_commas(strip_comments(path.read_text())))
PY

log "Checking Brewfile and LaunchAgent"
ruby -c Brewfile >/dev/null
plutil -lint Library/LaunchAgents/com.biboy.openusage.plist >/dev/null

log "Checking generated-state boundaries"
[[ ! -e .config/nvim/lazy-lock.json ]]
[[ ! -e .config/tmux/plugins.lock ]]
[[ ! -e .config/yazi/package.toml ]]
[[ -z "$(find .codex/skills -type f -print -quit 2>/dev/null)" ]]

while IFS= read -r plugin; do
  [[ -n "$plugin" ]] || continue
  rg -q "/${plugin}'" .tmux.conf
done <.config/tmux/plugins.txt

log "Building SketchyBar helpers"
make -C .config/sketchybar/helpers/event_providers
make -C .config/sketchybar/helpers/menus

log "Simulating a clean Stow deployment"
test_home="$(mktemp -d)"
trap 'rm -r -- "$test_home"' EXIT
mkdir -p \
  "$test_home/.config/zed" \
  "$test_home/.config/yazi" \
  "$test_home/.codex" \
  "$test_home/Library/LaunchAgents"
stow --simulate --target="$test_home" .

log "Checking patch whitespace"
git diff --check

printf "All checks passed.\n"
