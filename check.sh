#!/usr/bin/env zsh
set -euo pipefail

ROOT="${0:A:h}"
cd "$ROOT"
source "$ROOT/lib/brew_bundle.zsh"

CHECK_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-check.XXXXXX")"
TMUX_WORK_DIR="$(mktemp -d /tmp/dotfiles-tmux.XXXXXX)"
TMUX_SOCKET="dotfiles-check-$$"
TMUX_STARTED=0

cleanup() {
  if (( TMUX_STARTED )); then
    TMUX_TMPDIR="$TMUX_WORK_DIR" tmux -L "$TMUX_SOCKET" \
      kill-server >/dev/null 2>&1 || true
  fi
  rm -r -- "$CHECK_WORK_DIR" "$TMUX_WORK_DIR"
}
trap cleanup EXIT

log() {
  printf "==> %s\n" "$*"
}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    printf "Missing checker dependency: %s\n" "$1" >&2
    exit 1
  }
}

assert_line() {
  local output="$1"
  local expected="$2"
  grep -Fxq -- "$expected" <<<"$output" || {
    printf "Missing expected output: %s\n" "$expected" >&2
    exit 1
  }
}

for command in bash brew clang git jq json5 luac magick make nvim plutil python3 rg ruby stow tmux zsh; do
  require "$command"
done

log "Checking shell syntax"
zsh -n setup.sh check.sh lib/brew_bundle.zsh home/.p10k.zsh home/.zprofile home/.zshrc \
  home/.config/aerospace/scripts/resize-edge \
  home/.config/sketchybar/scripts/ai_usage.sh
bash -n \
  home/bin/abs \
  home/bin/ip \
  home/.config/tmux/scripts/copy_to_clipboard.sh \
  home/.config/tmux/scripts/move_window_to_session.sh \
  home/.config/tmux/scripts/new_session.sh \
  home/.config/tmux/scripts/rename_session_prompt.sh \
  home/.config/tmux/scripts/session_created.sh \
  home/.config/tmux/tmux-status/left.sh

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
while IFS= read -r file; do
  [[ -f "$file" ]] && json5 --validate "$file"
done < <(git ls-files '*.json' '*.jsonc')
jq empty home/.config/nvim/lazyvim.json
jq empty home/.config/nvim/lazy-lock.json
NVIM_LOG_FILE=/dev/null nvim -i NONE --headless \
  '+lua assert(require("lazy.core.config").options.lockfile == vim.fn.stdpath("config") .. "/lazy-lock.json")' \
  +qa

log "Checking Brewfile and LaunchAgent"
ruby -c Brewfile >/dev/null
plutil -lint home/Library/LaunchAgents/com.biboy.openusage.plist >/dev/null

log "Checking Brew bundle"
bundle_cask_skip="$(brew_bundle_cask_skip)"
HOMEBREW_BUNDLE_CASK_SKIP="$bundle_cask_skip" \
  brew bundle check --file="$ROOT/Brewfile" --verbose

log "Reporting unmanaged Brew dependencies"
brew_bundle_report_extras "$ROOT/Brewfile"

log "Checking AI usage fixtures"
fixture_root="$CHECK_WORK_DIR/openusage"
bar_root="$CHECK_WORK_DIR/bars"
mkdir -p "$fixture_root"/{object,array,empty,malformed} "$bar_root"
for provider in codex claude; do
  jq -n --arg provider "$provider" '
    {
      displayName: ($provider + " fixture"),
      plan: "test",
      fetchedAt: "2026-07-29T00:00:00Z",
      lines: [
        {type: "progress", label: "Session", limit: 100, used: 25},
        {type: "progress", label: "Weekly", limit: 100, used: 80}
      ]
    }
  ' >"$fixture_root/object/${provider}.json"
  jq -n --arg provider "$provider" '[
    {
      displayName: ($provider + " array fixture"),
      plan: "test",
      lines: [
        {type: "progress", label: "Session", limit: 100, used: 40},
        {type: "progress", label: "Weekly", limit: 100, used: 10}
      ]
    }
  ]' >"$fixture_root/array/${provider}.json"
  : >"$fixture_root/empty/${provider}.json"
  printf '{invalid\n' >"$fixture_root/malformed/${provider}.json"
done

object_output="$(OPENUSAGE_FIXTURE_DIR="$fixture_root/object" AI_USAGE_BAR_DIR="$bar_root" \
  zsh home/.config/sketchybar/scripts/ai_usage.sh)"
array_output="$(OPENUSAGE_FIXTURE_DIR="$fixture_root/array" AI_USAGE_BAR_DIR="$bar_root" \
  zsh home/.config/sketchybar/scripts/ai_usage.sh)"
empty_output="$(OPENUSAGE_FIXTURE_DIR="$fixture_root/empty" AI_USAGE_BAR_DIR="$bar_root" \
  zsh home/.config/sketchybar/scripts/ai_usage.sh)"
malformed_output="$(OPENUSAGE_FIXTURE_DIR="$fixture_root/malformed" AI_USAGE_BAR_DIR="$bar_root" \
  zsh home/.config/sketchybar/scripts/ai_usage.sh)"

for provider in codex claude; do
  assert_line "$object_output" "${provider}_status=ok"
  assert_line "$object_output" "${provider}_session=75"
  assert_line "$object_output" "${provider}_weekly=20"
  assert_line "$array_output" "${provider}_status=ok"
  assert_line "$array_output" "${provider}_session=60"
  assert_line "$array_output" "${provider}_weekly=90"
  assert_line "$empty_output" "${provider}_status=empty"
  assert_line "$malformed_output" "${provider}_status=parse_error"
done

log "Checking generated-state boundaries"
[[ ! -e home/.config/tmux/plugins.lock ]]
[[ -z "$(find home/.codex/skills -type f -print -quit 2>/dev/null)" ]]
rg -q 'use = "yazi-rs/flavors:catppuccin-mocha"' home/.config/yazi/package.toml

while IFS= read -r plugin; do
  [[ -n "$plugin" ]] || continue
  rg -q "/${plugin}'" home/.tmux.conf
done <home/.config/tmux/plugins.txt

log "Building and analyzing SketchyBar helpers"
helper_bin_dir="$CHECK_WORK_DIR/helpers"
strict_cflags="-std=c99 -O2 -Wall -Wextra -Wpedantic -Wconversion -Wshadow -Werror"
make -C home/.config/sketchybar/helpers/event_providers \
  CC=clang CFLAGS="$strict_cflags" BINDIR="$helper_bin_dir"
make -C home/.config/sketchybar/helpers/menus \
  CC=clang CFLAGS="$strict_cflags" BINDIR="$helper_bin_dir"
for source in \
  home/.config/sketchybar/helpers/event_providers/cpu_load/cpu_load.c \
  home/.config/sketchybar/helpers/event_providers/network_load/network_load.c \
  home/.config/sketchybar/helpers/menus/menus.c; do
  clang --analyze -std=c99 -Wall -Wextra \
    -Xanalyzer -analyzer-output=text "$source"
done

log "Parsing tmux configuration in an isolated server"
TMUX_TMPDIR="$TMUX_WORK_DIR" tmux -L "$TMUX_SOCKET" \
  -f "$ROOT/home/.tmux.conf" \
  new-session -d -s dotfiles-check
TMUX_STARTED=1
TMUX_TMPDIR="$TMUX_WORK_DIR" tmux -L "$TMUX_SOCKET" \
  show-options -g status-interval >/dev/null
TMUX_TMPDIR="$TMUX_WORK_DIR" tmux -L "$TMUX_SOCKET" \
  list-keys -T root >/dev/null
TMUX_TMPDIR="$TMUX_WORK_DIR" tmux -L "$TMUX_SOCKET" kill-server
TMUX_STARTED=0

log "Checking home package source boundaries"
while IFS= read -r -d '' file; do
  if ! git ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
    printf "Untracked file in home package: %s\n" "$file" >&2
    exit 1
  fi
done < <(find home \( -type f -o -type l \) -print0)
if [[ -n "$(git ls-files --others --ignored --exclude-standard -- home)" ]]; then
  printf "Ignored generated content found inside home package.\n" >&2
  exit 1
fi

log "Simulating a clean Stow deployment"
test_home="$CHECK_WORK_DIR/home"
mkdir -p \
  "$test_home/.config/zed" \
  "$test_home/.config/yazi" \
  "$test_home/.codex" \
  "$test_home/Library/LaunchAgents"
stow --dir="$ROOT" --simulate --target="$test_home" home

log "Checking patch whitespace"
git diff --check HEAD

printf "All checks passed.\n"
