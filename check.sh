#!/usr/bin/env zsh
set -euo pipefail

unset GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES

ROOT="${0:A:h}"
cd "$ROOT"

RUN_LIVE_CHECKS=0
FOLDING_MANIFEST="$ROOT/stow-target-dirs.txt"
INSTALLED_XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

usage() {
  printf "usage: zsh check.sh [--live]\n"
}

while (( $# )); do
  case "$1" in
    --live)
      RUN_LIVE_CHECKS=1
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf "Unknown option: %s\n" "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

CHECK_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-check.XXXXXX")"
CHECK_WORK_DIR="${CHECK_WORK_DIR:A}"
ISOLATED_HOME="$CHECK_WORK_DIR/isolated-home"
ISOLATED_TMP="$CHECK_WORK_DIR/tmp"
ISOLATED_ZDOTDIR="$CHECK_WORK_DIR/zdotdir"
STOW_CONFIG_HOME="$CHECK_WORK_DIR/stow-home"
CANDIDATE_ROOT="$CHECK_WORK_DIR/candidate"
HEAD_ARCHIVE_ROOT="$CHECK_WORK_DIR/head-archive"
TEMP_GIT_INDEX="$CHECK_WORK_DIR/git-index"
TEMP_GIT_OBJECTS="$CHECK_WORK_DIR/git-objects"
REAL_GIT_INDEX_SNAPSHOT="$CHECK_WORK_DIR/real-git-index"
TMUX_SOCKET="$CHECK_WORK_DIR/tmux.sock"
TMUX_STARTED=0

mkdir -p \
  "$ISOLATED_HOME" \
  "$ISOLATED_TMP" \
  "$ISOLATED_ZDOTDIR" \
  "$STOW_CONFIG_HOME" \
  "$CANDIDATE_ROOT" \
  "$HEAD_ARCHIVE_ROOT"
mkdir -p "$TEMP_GIT_OBJECTS"

ISOLATED_ENV=(
  "HOME=$ISOLATED_HOME"
  "XDG_CONFIG_HOME=$ISOLATED_HOME/.config"
  "XDG_DATA_HOME=$ISOLATED_HOME/.local/share"
  "XDG_CACHE_HOME=$ISOLATED_HOME/.cache"
  "XDG_STATE_HOME=$ISOLATED_HOME/.local/state"
  "PYTHONDONTWRITEBYTECODE=1"
  "TMPDIR=$ISOLATED_TMP"
  "TMUX="
  "ZDOTDIR=$ISOLATED_ZDOTDIR"
)

cleanup() {
  if (( TMUX_STARTED )); then
    env "${ISOLATED_ENV[@]}" tmux -S "$TMUX_SOCKET" \
      kill-server >/dev/null 2>&1 || true
  fi
  rm -r -- "$CHECK_WORK_DIR"
}
trap cleanup EXIT

[[ "$CHECK_WORK_DIR/" != "$ROOT/"* ]] || {
  printf "Checker temporary directory must be outside the repository.\n" >&2
  exit 1
}

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

assert_bar() {
  local output="$1"
  local provider="$2"
  local bar_path dimensions
  bar_path="$(
    awk -F= -v key="${provider}_bar" \
      '$1 == key { print substr($0, index($0, "=") + 1); exit }' \
      <<<"$output"
  )"
  [[ -n "$bar_path" && -f "$bar_path" ]] || {
    printf "Missing generated bar for %s: %s\n" "$provider" "$bar_path" >&2
    exit 1
  }
  dimensions="$(magick identify -format '%wx%h' "$bar_path")"
  [[ "$dimensions" == "52x14" ]] || {
    printf "Unexpected bar dimensions for %s: %s\n" "$provider" "$dimensions" >&2
    exit 1
  }
}

create_stow_target() {
  local target_root="$1"
  local target_dir

  while IFS= read -r target_dir; do
    [[ -n "$target_dir" ]] || continue
    mkdir -p "$target_root/$target_dir"
  done <<<"$manifest_target_dirs"
}

write_stow_plan() {
  local source_root="$1"
  local target_root="$2"
  local output_file="$3"
  shift 3

  (
    cd "$ISOLATED_TMP"
    env HOME="$STOW_CONFIG_HOME" LC_ALL=C stow \
      --dir="$source_root" --simulate --verbose=2 --target="$target_root" \
      "$@" home
  ) 2>&1 \
    | sed -nE \
      -e 's/^[[:space:]]*LINK: (.*) => .*/LINK \1/p' \
      -e 's/^[[:space:]]*(MKDIR|UNLINK|RMDIR): (.*)$/\1 \2/p' \
    | LC_ALL=C sort >"$output_file"
}

for command in \
  awk bash clang cmp diff find git grep jq json5 ln lua luac magick make plutil \
  python3 rg ruby sed sort stow tar zsh; do
  require "$command"
done

[[ -z "$(git ls-files --unmerged)" ]] || {
  printf "Cannot snapshot a Git index with unresolved merges.\n" >&2
  exit 1
}
real_git_index="$(git rev-parse --path-format=absolute --git-path index)"
[[ "$real_git_index" == /* ]] || real_git_index="$ROOT/$real_git_index"
real_git_objects="$(git rev-parse --path-format=absolute --git-path objects)"
[[ "$real_git_objects" == /* ]] || real_git_objects="$ROOT/$real_git_objects"
[[ -f "$real_git_index" ]] || {
  printf "Missing Git index: %s\n" "$real_git_index" >&2
  exit 1
}
cp "$real_git_index" "$TEMP_GIT_INDEX"
cp "$real_git_index" "$REAL_GIT_INDEX_SNAPSHOT"
chmod u+w "$TEMP_GIT_INDEX"
SNAPSHOT_GIT_ENV=(
  "GIT_INDEX_FILE=$TEMP_GIT_INDEX"
  "GIT_OBJECT_DIRECTORY=$TEMP_GIT_OBJECTS"
  "GIT_ALTERNATE_OBJECT_DIRECTORIES=$real_git_objects"
)
snapshot_git() {
  env "${SNAPSHOT_GIT_ENV[@]}" git "$@"
}
snapshot_git add -A -- :/
snapshot_git diff --quiet --no-ext-diff -- :/ || {
  printf "Worktree changed while the temporary Git snapshot was created.\n" >&2
  exit 1
}
snapshot_git ls-files --error-unmatch -- \
  stow-target-dirs.txt home/.stow-local-ignore >/dev/null
snapshot_git checkout-index --all --prefix="$CANDIDATE_ROOT/"
cmp -s "$real_git_index" "$REAL_GIT_INDEX_SNAPSHOT" || {
  printf "The real Git index changed while preparing the candidate snapshot.\n" >&2
  exit 1
}

log "Checking shell syntax"
zsh -n setup.sh check.sh lib/brew_bundle.zsh home/.p10k.zsh home/.zprofile home/.zshrc \
  home/.config/aerospace/scripts/resize-edge \
  home/.config/sketchybar/scripts/ai_usage.sh \
  home/.config/sketchybar/scripts/media_state.sh
/bin/bash -n \
  home/bin/abs \
  home/bin/ip \
  home/.config/tmux/scripts/copy_to_clipboard.sh \
  home/.config/tmux/scripts/move_window_to_session.sh \
  home/.config/tmux/scripts/new_session.sh \
  home/.config/tmux/scripts/rename_session_prompt.sh \
  home/.config/tmux/scripts/session_created.sh \
  home/.config/tmux/tmux-status/left.sh

log "Checking public IP helper behavior"
IP_FIXTURE_DIR="$CHECK_WORK_DIR/ip-fixtures"
IP_SLOW_MARKER="$IP_FIXTURE_DIR/slow-started"
mkdir -p "$IP_FIXTURE_DIR"

cat >"$IP_FIXTURE_DIR/curl" <<'BASH'
#!/bin/bash
set -euo pipefail

[[ "$#" -eq 7 ]]
[[ "$1" == "-4" && "$2" == "-fsS" ]]
[[ "$3" == "--max-time" && "$4" == "2" ]]
[[ "$5" == "--retry" && "$6" == "0" ]]
url="$7"
printf '%s\n' "$url" >>"$IP_CURL_LOG"

case "$IP_MOCK_SCENARIO:$url" in
  primary_success:https://api.ipify.org)
    printf '203.0.113.7\n'
    ;;
  invalid_primary_fallback:https://api.ipify.org)
    printf '999.1.2.3\n'
    ;;
  invalid_primary_fallback:https://ipv4.icanhazip.com)
    printf '198.51.100.17\n'
    ;;
  invalid_primary_fallback:*)
    exit 22
    ;;
  race:https://api.ipify.org)
    exit 22
    ;;
  race:https://ipv4.icanhazip.com)
    : >"$IP_SLOW_MARKER"
    sleep 8
    exit 22
    ;;
  race:https://ipinfo.io/ip)
    for _ in {1..100}; do
      [[ -e "$IP_SLOW_MARKER" ]] && break
      sleep 0.01
    done
    [[ -e "$IP_SLOW_MARKER" ]]
    printf '192.0.2.44\n'
    ;;
  race:*)
    sleep 8
    exit 22
    ;;
  all_fail:*)
    exit 22
    ;;
  *)
    exit 64
    ;;
esac
BASH

cat >"$IP_FIXTURE_DIR/dig" <<'BASH'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >>"$IP_DIG_LOG"
exit 9
BASH
chmod +x "$IP_FIXTURE_DIR/curl" "$IP_FIXTURE_DIR/dig"

typeset -g \
  IP_CASE_OUTPUT="" \
  IP_CASE_EXIT=0 \
  IP_CASE_CURL_LOG="" \
  IP_CASE_DIG_LOG="" \
  IP_CASE_STDERR=""

run_ip_case() {
  local scenario="$1"

  IP_CASE_CURL_LOG="$IP_FIXTURE_DIR/$scenario.curl.log"
  IP_CASE_DIG_LOG="$IP_FIXTURE_DIR/$scenario.dig.log"
  IP_CASE_STDERR="$IP_FIXTURE_DIR/$scenario.stderr"
  : >"$IP_CASE_CURL_LOG"
  : >"$IP_CASE_DIG_LOG"
  rm -f -- "$IP_SLOW_MARKER"

  if IP_CASE_OUTPUT="$(
    env "${ISOLATED_ENV[@]}" \
      IP_CURL_BIN="$IP_FIXTURE_DIR/curl" \
      IP_DIG_BIN="$IP_FIXTURE_DIR/dig" \
      IP_MOCK_SCENARIO="$scenario" \
      IP_CURL_LOG="$IP_CASE_CURL_LOG" \
      IP_DIG_LOG="$IP_CASE_DIG_LOG" \
      IP_SLOW_MARKER="$IP_SLOW_MARKER" \
      /bin/bash "$ROOT/home/bin/ip" 2>"$IP_CASE_STDERR"
  )"; then
    IP_CASE_EXIT=0
  else
    IP_CASE_EXIT=$?
  fi
}

run_ip_case primary_success
(( IP_CASE_EXIT == 0 ))
[[ "$IP_CASE_OUTPUT" == "203.0.113.7" ]]
[[ ! -s "$IP_CASE_STDERR" ]]
[[ "$(<"$IP_CASE_CURL_LOG")" == "https://api.ipify.org" ]]
[[ ! -s "$IP_CASE_DIG_LOG" ]]

run_ip_case invalid_primary_fallback
(( IP_CASE_EXIT == 0 ))
[[ "$IP_CASE_OUTPUT" == "198.51.100.17" ]]
[[ ! -s "$IP_CASE_STDERR" ]]
grep -Fxq 'https://api.ipify.org' "$IP_CASE_CURL_LOG"
grep -Fxq 'https://ipv4.icanhazip.com' "$IP_CASE_CURL_LOG"
[[ ! -s "$IP_CASE_DIG_LOG" ]]

zmodload zsh/datetime
typeset -F race_started race_elapsed
race_started=$EPOCHREALTIME
run_ip_case race
race_elapsed=$(( EPOCHREALTIME - race_started ))
(( IP_CASE_EXIT == 0 ))
[[ "$IP_CASE_OUTPUT" == "192.0.2.44" ]]
[[ ! -s "$IP_CASE_STDERR" ]]
[[ -e "$IP_SLOW_MARKER" ]]
(( race_elapsed < 3.0 )) || {
  printf "Public IP fallback waited %.3fs for a slow endpoint.\n" \
    "$race_elapsed" >&2
  exit 1
}
grep -Fxq 'https://ipv4.icanhazip.com' "$IP_CASE_CURL_LOG"
grep -Fxq 'https://ipinfo.io/ip' "$IP_CASE_CURL_LOG"
[[ ! -s "$IP_CASE_DIG_LOG" ]]

run_ip_case all_fail
(( IP_CASE_EXIT == 1 ))
[[ -z "$IP_CASE_OUTPUT" ]]
[[ "$(<"$IP_CASE_STDERR")" == "unable to determine public IPv4" ]]
[[ "$(awk 'END { print NR }' "$IP_CASE_CURL_LOG")" == 5 ]]
for endpoint in \
  'https://api.ipify.org' \
  'https://ipv4.icanhazip.com' \
  'https://ipinfo.io/ip' \
  'https://ifconfig.co/ip' \
  'https://checkip.amazonaws.com'; do
  grep -Fxq "$endpoint" "$IP_CASE_CURL_LOG"
done
[[ "$(<"$IP_CASE_DIG_LOG")" == \
  "+short -4 +time=1 +tries=1 myip.opendns.com @resolver1.opendns.com" ]]

log "Checking media-state helper behavior"
media_cache="$CHECK_WORK_DIR/media-cache"
mkdir -p "$media_cache"
media_playing_output="$(
  printf '%s\n' \
    '{"title":"Fixture Song","artist":"Fixture Artist","playbackRate":1,"clientBundleIdentifier":"com.spotify.client","artworkData":"iVBORw0KGgo="}' \
    | env "${ISOLATED_ENV[@]}" zsh \
      home/.config/sketchybar/scripts/media_state.sh --stdin "$media_cache"
)"
jq -e \
  --arg cache_prefix "$media_cache/media-artwork-" '
    .playing == true
      and .title == "Fixture Song"
      and .artist == "Fixture Artist"
      and (.artwork | startswith($cache_prefix))
  ' <<<"$media_playing_output" >/dev/null
media_artwork="$(jq -er '.artwork' <<<"$media_playing_output")"
[[ -s "$media_artwork" ]]

media_stopped_output="$(
  printf '%s\n' \
    '{"title":"Paused","playbackRate":0,"clientBundleIdentifier":"com.spotify.client"}' \
    | env "${ISOLATED_ENV[@]}" zsh \
      home/.config/sketchybar/scripts/media_state.sh --stdin "$media_cache"
)"
jq -e '. == {playing:false}' <<<"$media_stopped_output" >/dev/null

media_music_output="$(
  printf '%s\n' \
    '{"title":"Music Fixture","artist":"Fixture Artist","playbackRate":1,"clientBundleIdentifier":"com.apple.Music"}' \
    | env "${ISOLATED_ENV[@]}" zsh \
      home/.config/sketchybar/scripts/media_state.sh --stdin "$media_cache"
)"
jq -e \
  '.playing == true and .title == "Music Fixture" and .artwork == ""' \
  <<<"$media_music_output" >/dev/null

media_unrelated_output="$(
  printf '%s\n' \
    '{"title":"Browser Media","playbackRate":1,"clientBundleIdentifier":"com.google.Chrome","isMusicApp":true}' \
    | env "${ISOLATED_ENV[@]}" zsh \
      home/.config/sketchybar/scripts/media_state.sh --stdin "$media_cache"
)"
jq -e '. == {playing:false}' <<<"$media_unrelated_output" >/dev/null

media_malformed_output="$(
  printf '{invalid\n' \
    | env "${ISOLATED_ENV[@]}" zsh \
      home/.config/sketchybar/scripts/media_state.sh --stdin "$media_cache"
)"
jq -e '. == {playing:false}' <<<"$media_malformed_output" >/dev/null

media_invalid_artwork_output="$(
  printf '%s\n' \
    '{"title":"Bad Art","playbackRate":1,"clientBundleIdentifier":"com.spotify.client","artworkData":"%%%"}' \
    | env "${ISOLATED_ENV[@]}" zsh \
      home/.config/sketchybar/scripts/media_state.sh --stdin "$media_cache"
)"
jq -e \
  '.playing == true and .title == "Bad Art" and .artwork == ""' \
  <<<"$media_invalid_artwork_output" >/dev/null
[[ -z "$(find "$media_cache" -type f -name 'media-artwork.??????' -print -quit)" ]]

log "Checking setup command-line behavior"
setup_help="$(env "${ISOLATED_ENV[@]}" zsh setup.sh --help)"
grep -Fq 'usage:' <<<"$setup_help"
if env "${ISOLATED_ENV[@]}" zsh setup.sh --invalid-check-option \
  >"$CHECK_WORK_DIR/setup-invalid.out" 2>&1; then
  printf "setup.sh accepted an invalid option.\n" >&2
  exit 1
else
  setup_status=$?
  (( setup_status == 2 )) || {
    printf "setup.sh returned %d for an invalid option; expected 2.\n" "$setup_status" >&2
    exit 1
  }
fi

python3 - setup.sh <<'PY'
import sys
from pathlib import Path

guard = '''if [[ "${ZSH_EVAL_CONTEXT:-}" == toplevel ]]; then
  main "$@"
fi'''
text = Path(sys.argv[1]).read_text().rstrip()
if text.count(guard) != 1 or not text.endswith(guard):
    raise SystemExit("setup.sh must keep main behind its source-safe entry guard")
PY

log "Checking setup preflight isolation and conflict behavior"
SETUP_FIXTURE_ROOT="$CHECK_WORK_DIR/setup-preflight"
SETUP_FIXTURE_SOURCE="$SETUP_FIXTURE_ROOT/source"
SETUP_FIXTURE_HOME="$SETUP_FIXTURE_ROOT/home"
SETUP_FIXTURE_TMP="$SETUP_FIXTURE_ROOT/tmp"
SETUP_SNAPSHOT_DIR="$CHECK_WORK_DIR/setup-snapshots"
SETUP_POISON_MARKER="$SETUP_SNAPSHOT_DIR/poison"
mkdir -p \
  "$SETUP_FIXTURE_SOURCE/home/.config/kitty" \
  "$SETUP_FIXTURE_SOURCE/home/.config/zed" \
  "$SETUP_FIXTURE_SOURCE/home/.config/yazi" \
  "$SETUP_FIXTURE_SOURCE/home/.config/preflight-boundary" \
  "$SETUP_FIXTURE_SOURCE/home/.config/preflight-ignored" \
  "$SETUP_FIXTURE_SOURCE/home/.codex" \
  "$SETUP_FIXTURE_SOURCE/home/Library/LaunchAgents" \
  "$SETUP_FIXTURE_HOME/.config/preflight-boundary" \
  "$SETUP_FIXTURE_HOME/.config/preflight-ignored" \
  "$SETUP_FIXTURE_TMP" \
  "$SETUP_SNAPSHOT_DIR"
cp "$FOLDING_MANIFEST" "$SETUP_FIXTURE_SOURCE/stow-target-dirs.txt"
printf '.config/preflight-boundary\n' \
  >>"$SETUP_FIXTURE_SOURCE/stow-target-dirs.txt"
cp home/.stow-local-ignore \
  "$SETUP_FIXTURE_SOURCE/home/.stow-local-ignore"
printf '^/\\.config/preflight-ignored($|/)\n' \
  >>"$SETUP_FIXTURE_SOURCE/home/.stow-local-ignore"
printf 'font_family fixture\n' \
  >"$SETUP_FIXTURE_SOURCE/home/.config/kitty/kitty.conf"
printf 'foreign ignored state\n' \
  >"$SETUP_FIXTURE_HOME/.config/preflight-ignored/generated.txt"
printf '%s\n' --adopt '--ignore=^never-match-home$' \
  >"$SETUP_FIXTURE_HOME/.stowrc"
printf '%s\n' --no-folding '--ignore=^never-match-cwd$' \
  >"$SETUP_FIXTURE_TMP/.stowrc"

write_tree_snapshot() {
  python3 - "$1" <<'PY'
import hashlib
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])


def describe(path: Path, relative: str, kind: str, payload: str) -> None:
    metadata = path.lstat()
    mode = f"{stat.S_IMODE(metadata.st_mode):04o}"
    flags = getattr(metadata, "st_flags", 0)
    xattrs = []
    if hasattr(os, "listxattr"):
        for name in sorted(os.listxattr(path, follow_symlinks=False)):
            value = os.getxattr(path, name, follow_symlinks=False).hex()
            xattrs.append(f"{name}={value}")
    print(
        relative,
        kind,
        mode,
        metadata.st_uid,
        metadata.st_gid,
        flags,
        metadata.st_mtime_ns,
        ";".join(xattrs),
        payload,
        sep="\t",
    )


def visit(directory: Path) -> None:
    for entry in sorted(os.scandir(directory), key=lambda item: item.name):
        path = Path(entry.path)
        relative = path.relative_to(root).as_posix()
        if entry.is_symlink():
            describe(path, relative, "L", os.readlink(path))
        elif entry.is_dir(follow_symlinks=False):
            describe(path, relative, "D", "")
            visit(path)
        elif entry.is_file(follow_symlinks=False):
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            describe(path, relative, "F", digest)
        else:
            describe(path, relative, "O", "")


describe(root, ".", "D", "")
visit(root)
PY
}

run_setup_preflight() {
  local output_file="$1"
  local action="${2:-dotfiles}"
  local checkout="${3:-}"

  rm -f -- "$SETUP_POISON_MARKER"
  env \
    HOME="$SETUP_FIXTURE_HOME" \
    XDG_CONFIG_HOME="$SETUP_FIXTURE_HOME/.config" \
    XDG_DATA_HOME="$SETUP_FIXTURE_HOME/.local/share" \
    XDG_CACHE_HOME="$SETUP_FIXTURE_HOME/.cache" \
    XDG_STATE_HOME="$SETUP_FIXTURE_HOME/.local/state" \
    TMPDIR="$SETUP_FIXTURE_TMP" \
    PYTHONDONTWRITEBYTECODE=1 \
    STOW_DIR="$SETUP_FIXTURE_ROOT/hostile-stow-dir" \
    zsh -fc '
      setopt FUNCTION_ARGZERO
      cd "$6"
      source "$1"
      DOTFILES_DIR="${2:A}"
      STOW_IGNORE_PATTERNS=()
      STOW_IGNORE_PATTERNS_LOADED=0
      POISON_MARKER="$3"
      PREFLIGHT_ACTION="$4"
      REAL_GIT="$(command -v git)"
      REAL_STOW="$(command -v stow)"
      poison() { print -r -- "$1" >>"$POISON_MARKER"; return 97; }
      main() { poison main; }
      ensure_latest_git_checkout() { poison clone; }
      install_homebrew() { poison homebrew; }
      install_brew_packages() { poison brew; }
      link_dotfiles() { poison link; }
      git() {
        if (( $# == 4 )) && [[ "$1" == -C && "$3" == status \
          && "$4" == --porcelain ]]; then
          command "$REAL_GIT" "$@"
        elif (( $# == 5 )) && [[ "$1" == -C && "$3" == remote \
          && "$4" == get-url && "$5" == origin ]]; then
          command "$REAL_GIT" "$@"
        else
          poison git
        fi
      }
      stow() {
        local argument
        local simulated=0
        if [[ "$PWD" != "$STOW_CONFIG_CWD" \
          || "$HOME" != "$STOW_CONFIG_HOME" \
          || "${XDG_CONFIG_HOME:-}" != "$STOW_CONFIG_HOME/.config" \
          || -n "${STOW_DIR+x}" ]]; then
          poison stow-environment
          return 97
        fi
        for argument in "$@"; do
          [[ "$argument" == --simulate ]] && simulated=1
        done
        if [[ "$PREFLIGHT_ACTION" != stow-real-conflict ]]; then
          (( simulated )) || { poison stow; return 97; }
        fi
        command "$REAL_STOW" "$@"
      }
      brew() { poison brew; }
      curl() { poison curl; }
      defaults() { poison defaults; }
      launchctl() { poison launchctl; }
      mkdir() { poison mkdir; }
      mv() { poison mv; }
      open() { poison open; }
      osascript() { poison osascript; }
      rm() { poison rm; }
      sudo() { poison sudo; }
      xcodebuild() { poison xcodebuild; }
      case "$4" in
        dotfiles)
          preflight_dotfiles
          ;;
        git-checkout)
          preflight_git_checkout "$5"
          ;;
        github-checkout)
          preflight_github_checkout "nvm-sh/nvm" "$5"
          ;;
        stow-real-conflict)
          run_stow --dir="$DOTFILES_DIR" --restow --target="$HOME" home
          ;;
        *)
          exit 64
          ;;
      esac
    ' setup-preflight "$ROOT/setup.sh" "$SETUP_FIXTURE_SOURCE" \
      "$SETUP_POISON_MARKER" "$action" "$checkout" "$SETUP_FIXTURE_TMP" \
      >"$output_file" 2>&1
}

setup_before="$SETUP_SNAPSHOT_DIR/clean.before"
setup_after="$SETUP_SNAPSHOT_DIR/clean.after"
setup_output="$SETUP_SNAPSHOT_DIR/clean.out"
write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$setup_before"
run_setup_preflight "$setup_output" || {
  printf "Clean setup preflight fixture failed:\n" >&2
  sed 's/^/  /' "$setup_output" >&2
  exit 1
}
write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$setup_after"
cmp -s "$setup_before" "$setup_after" || {
  printf "Setup preflight mutated its clean target fixture:\n" >&2
  diff -u "$setup_before" "$setup_after" >&2 || true
  exit 1
}
[[ ! -e "$SETUP_POISON_MARKER" ]]

printf 'machine-local config\n' \
  >"$SETUP_FIXTURE_SOURCE/home/.codex/config.toml"
ln -s "$SETUP_FIXTURE_SOURCE/home/.codex" \
  "$SETUP_FIXTURE_HOME/.codex"
setup_before="$SETUP_SNAPSHOT_DIR/folded.before"
setup_after="$SETUP_SNAPSHOT_DIR/folded.after"
setup_output="$SETUP_SNAPSHOT_DIR/folded.out"
write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$setup_before"
if run_setup_preflight "$setup_output"; then
  printf "Setup preflight accepted ignored data in a folded container.\n" >&2
  exit 1
fi
grep -Fxq \
  "Ignored machine-local data would be stranded by Stow migration: $SETUP_FIXTURE_SOURCE/home/.codex/config.toml" \
  "$setup_output"
write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$setup_after"
cmp -s "$setup_before" "$setup_after" || {
  printf "Setup preflight mutated its folded-container fixture:\n" >&2
  diff -u "$setup_before" "$setup_after" >&2 || true
  exit 1
}
[[ ! -e "$SETUP_POISON_MARKER" ]]
rm -f -- \
  "$SETUP_FIXTURE_HOME/.codex" \
  "$SETUP_FIXTURE_SOURCE/home/.codex/config.toml"

mkdir -p "$SETUP_FIXTURE_HOME/.config/kitty"
printf 'foreign managed state\n' \
  >"$SETUP_FIXTURE_HOME/.config/kitty/kitty.conf"
setup_before="$SETUP_SNAPSHOT_DIR/conflict.before"
setup_after="$SETUP_SNAPSHOT_DIR/conflict.after"
setup_output="$SETUP_SNAPSHOT_DIR/conflict.out"
write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$setup_before"
if run_setup_preflight "$setup_output"; then
  printf "Setup preflight accepted a managed-file conflict.\n" >&2
  exit 1
fi
grep -Fq \
  "Stow conflict: $SETUP_FIXTURE_HOME/.config/kitty/kitty.conf already exists." \
  "$setup_output"
write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$setup_after"
cmp -s "$setup_before" "$setup_after" || {
  printf "Setup preflight mutated its conflict target fixture:\n" >&2
  diff -u "$setup_before" "$setup_after" >&2 || true
  exit 1
}
[[ ! -e "$SETUP_POISON_MARKER" ]]

setup_before="$SETUP_SNAPSHOT_DIR/stow-real.before"
setup_after="$SETUP_SNAPSHOT_DIR/stow-real.after"
setup_output="$SETUP_SNAPSHOT_DIR/stow-real.out"
write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$setup_before"
if run_setup_preflight "$setup_output" stow-real-conflict; then
  printf "Setup Stow accepted a conflict through hostile resource options.\n" >&2
  exit 1
fi
grep -Fq '../source/home/.config/kitty/kitty.conf' "$setup_output"
grep -Fq -- '--adopt not specified' "$setup_output"
write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$setup_after"
cmp -s "$setup_before" "$setup_after" || {
  printf "Setup Stow mutated its hostile-resource fixture:\n" >&2
  diff -u "$setup_before" "$setup_after" >&2 || true
  exit 1
}
[[ ! -e "$SETUP_POISON_MARKER" ]]

corrupt_checkout="$SETUP_FIXTURE_HOME/.nvm"
mkdir -p "$corrupt_checkout/.git/objects"
printf 'not-a-valid-head\n' >"$corrupt_checkout/.git/HEAD"
setup_before="$SETUP_SNAPSHOT_DIR/corrupt-git.before"
setup_after="$SETUP_SNAPSHOT_DIR/corrupt-git.after"
setup_output="$SETUP_SNAPSHOT_DIR/corrupt-git.out"
write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$setup_before"
if run_setup_preflight "$setup_output" git-checkout "$corrupt_checkout"; then
  printf "Setup preflight accepted a corrupt Git checkout.\n" >&2
  exit 1
fi
grep -Fq "Could not inspect Git checkout $corrupt_checkout:" "$setup_output"
write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$setup_after"
cmp -s "$setup_before" "$setup_after" || {
  printf "Setup preflight mutated its corrupt Git fixture:\n" >&2
  diff -u "$setup_before" "$setup_after" >&2 || true
  exit 1
}
[[ ! -e "$SETUP_POISON_MARKER" ]]

wrong_origin_checkout="$SETUP_FIXTURE_HOME/wrong-nvm"
git init --quiet "$wrong_origin_checkout"
git -C "$wrong_origin_checkout" remote add origin \
  https://github.com/example/not-nvm.git
setup_before="$SETUP_SNAPSHOT_DIR/wrong-origin.before"
setup_after="$SETUP_SNAPSHOT_DIR/wrong-origin.after"
setup_output="$SETUP_SNAPSHOT_DIR/wrong-origin.out"
write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$setup_before"
if run_setup_preflight "$setup_output" github-checkout "$wrong_origin_checkout"; then
  printf "Setup preflight accepted a dependency checkout with the wrong origin.\n" >&2
  exit 1
fi
grep -Fq \
  "Unexpected origin for Git checkout nvm-sh/nvm at $wrong_origin_checkout: https://github.com/example/not-nvm.git" \
  "$setup_output"
write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$setup_after"
cmp -s "$setup_before" "$setup_after" || {
  printf "Setup preflight mutated its wrong-origin Git fixture:\n" >&2
  diff -u "$setup_before" "$setup_after" >&2 || true
  exit 1
}
[[ ! -e "$SETUP_POISON_MARKER" ]]

printf '../escape\n' >>"$SETUP_FIXTURE_SOURCE/stow-target-dirs.txt"
setup_before="$SETUP_SNAPSHOT_DIR/invalid.before"
setup_after="$SETUP_SNAPSHOT_DIR/invalid.after"
setup_output="$SETUP_SNAPSHOT_DIR/invalid.out"
write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$setup_before"
if run_setup_preflight "$setup_output"; then
  printf "Setup preflight accepted an unsafe folding boundary.\n" >&2
  exit 1
fi
grep -Fq 'Invalid Stow target directory: ../escape' "$setup_output"
write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$setup_after"
cmp -s "$setup_before" "$setup_after" || {
  printf "Setup preflight mutated its invalid-manifest target fixture:\n" >&2
  diff -u "$setup_before" "$setup_after" >&2 || true
  exit 1
}
[[ ! -e "$SETUP_POISON_MARKER" ]]

log "Checking setup NVM activation"
NVM_FIXTURE_HOME="$SETUP_SNAPSHOT_DIR/nvm-home"
NVM_FIXTURE_BIN="$NVM_FIXTURE_HOME/.nvm/versions/node/v1.2.3/bin"
BREW_FIXTURE_BIN="$SETUP_SNAPSHOT_DIR/homebrew/bin"
mkdir -p "$NVM_FIXTURE_HOME/.nvm" "$NVM_FIXTURE_BIN" "$BREW_FIXTURE_BIN"
printf '#!/bin/sh\nexit 0\n' >"$NVM_FIXTURE_BIN/npm"
printf '#!/bin/sh\nexit 0\n' >"$BREW_FIXTURE_BIN/npm"
chmod +x "$NVM_FIXTURE_BIN/npm" "$BREW_FIXTURE_BIN/npm"
cat >"$NVM_FIXTURE_HOME/.nvm/nvm.sh" <<'ZSH'
nvm() {
  local command="$1"
  local entry
  local -a updated_path

  case "$command" in
    install | alias)
      return 0
      ;;
    version)
      print -r -- v1.2.3
      ;;
    deactivate)
      for entry in "${path[@]}"; do
        [[ "$entry" == "$NVM_FIXTURE_BIN" ]] || updated_path+=("$entry")
      done
      path=("${updated_path[@]}")
      ;;
    use)
      for entry in "${path[@]}"; do
        [[ "$entry" == "$NVM_FIXTURE_BIN" ]] && return 0
      done
      path=("$NVM_FIXTURE_BIN" "${path[@]}")
      ;;
    *)
      return 1
      ;;
  esac
}
ZSH
env \
  HOME="$NVM_FIXTURE_HOME" \
  NVM_FIXTURE_BIN="$NVM_FIXTURE_BIN" \
  PATH="$BREW_FIXTURE_BIN:$NVM_FIXTURE_BIN:/usr/bin:/bin" \
  zsh -fc '
    setopt FUNCTION_ARGZERO
    source "$1"
    ensure_latest_git_checkout() { :; }
    install_nvm_node >/dev/null
    [[ "$(command -v npm)" == "$NVM_FIXTURE_BIN/npm" ]]
  ' setup-nvm "$ROOT/setup.sh"

log "Checking Xcode license preflight"
env zsh -fc '
  setopt FUNCTION_ARGZERO
  source "$1"

  XCODEBUILD_CALLS=0
  XCODEBUILD_EXIT=1
  xcode-select() { print -r -- "$DEVELOPER_DIR"; }
  have() { [[ "$1" == xcodebuild ]]; }
  xcodebuild() {
    (( XCODEBUILD_CALLS++ ))
    return "$XCODEBUILD_EXIT"
  }

  DEVELOPER_DIR=/Library/Developer/CommandLineTools
  preflight_xcode_license
  (( NEEDS_XCODE_LICENSE == 0 ))
  (( XCODEBUILD_CALLS == 0 ))

  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  preflight_xcode_license
  (( NEEDS_XCODE_LICENSE == 1 ))
  (( XCODEBUILD_CALLS == 1 ))

  XCODEBUILD_EXIT=0
  preflight_xcode_license
  (( NEEDS_XCODE_LICENSE == 0 ))
  (( XCODEBUILD_CALLS == 2 ))
' setup-xcode "$ROOT/setup.sh"

log "Checking trackpad defaults"
TRACKPAD_DEFAULTS_LOG="$CHECK_WORK_DIR/trackpad-defaults.log"
env TRACKPAD_DEFAULTS_LOG="$TRACKPAD_DEFAULTS_LOG" zsh -fc '
  setopt FUNCTION_ARGZERO
  source "$1"
  log() { :; }
  osascript() { :; }
  defaults() { print -r -- "$*" >>"$TRACKPAD_DEFAULTS_LOG"; }
  sudo_run() { :; }

  setup_system_preferences
  grep -Fxq -- "write com.apple.AppleMultitouchTrackpad Clicking -bool true" \
    "$TRACKPAD_DEFAULTS_LOG"
  grep -Fxq -- "write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true" \
    "$TRACKPAD_DEFAULTS_LOG"
  grep -Fxq -- "-currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1" \
    "$TRACKPAD_DEFAULTS_LOG"
' setup-trackpad "$ROOT/setup.sh"

log "Checking startup sound defaults"
STARTUP_SOUND_LOG="$CHECK_WORK_DIR/startup-sound.log"
env STARTUP_SOUND_LOG="$STARTUP_SOUND_LOG" zsh -fc '
  setopt FUNCTION_ARGZERO
  source "$1"
  log() { :; }
  osascript() { :; }
  defaults() { :; }
  sudo_run() { print -r -- "$*" >>"$STARTUP_SOUND_LOG"; }

  setup_system_preferences
  grep -Fxq -- "nvram StartupMute=%01" "$STARTUP_SOUND_LOG"
  if grep -Fq -- "SystemAudioVolume" "$STARTUP_SOUND_LOG"; then
    printf "Setup still writes the legacy SystemAudioVolume NVRAM value.\n" >&2
    exit 1
  fi
' setup-startup-sound "$ROOT/setup.sh"

log "Checking setup service failure propagation"
SERVICE_FIXTURE_LOG="$SETUP_SNAPSHOT_DIR/services.log"
env SERVICE_FIXTURE_LOG="$SERVICE_FIXTURE_LOG" zsh -fc '
  setopt FUNCTION_ARGZERO
  source "$1"
  skip() { :; }
  sleep() { :; }

  expect_failure() {
    if "$@"; then
      printf "Expected setup service failure: %s\n" "$1" >&2
      exit 1
    fi
  }

  pgrep() { return 1; }
  open() { return 1; }
  expect_failure restart_openusage

  have() { [[ "$1" == aerospace ]]; }
  open() { return 0; }
  wait_for_aerospace() { return 1; }
  expect_failure restart_aerospace

  have() { [[ "$1" == sketchybar ]]; }
  brew() { return 0; }
  sketchybar() { return 1; }
  expect_failure restart_sketchybar

  have() { [[ "$1" == skhd ]]; }
  skhd() { return 0; }
  launchctl() { return 1; }
  id() { print -r -- 501; }
  expect_failure restart_skhd

  OPENUSAGE_EXIT=0
  AEROSPACE_EXIT=0
  SKETCHYBAR_EXIT=0
  SKHD_EXIT=0
  restart_openusage() {
    print -r -- openusage >>"$SERVICE_FIXTURE_LOG"
    return "$OPENUSAGE_EXIT"
  }
  restart_aerospace() {
    print -r -- aerospace >>"$SERVICE_FIXTURE_LOG"
    return "$AEROSPACE_EXIT"
  }
  restart_sketchybar() {
    print -r -- sketchybar >>"$SERVICE_FIXTURE_LOG"
    return "$SKETCHYBAR_EXIT"
  }
  restart_skhd() {
    print -r -- skhd >>"$SERVICE_FIXTURE_LOG"
    return "$SKHD_EXIT"
  }

  assert_service_case() {
    local expected_exit="$1"
    local expected_calls="$2"
    local actual_exit
    : >"$SERVICE_FIXTURE_LOG"
    if restart_services >/dev/null 2>&1; then
      actual_exit=0
    else
      actual_exit=$?
    fi
    [[ "$actual_exit" == "$expected_exit" ]]
    [[ "$(<"$SERVICE_FIXTURE_LOG")" == "$expected_calls" ]]
  }

  all_calls="openusage
aerospace
sketchybar
skhd"
  assert_service_case 0 "$all_calls"
  OPENUSAGE_EXIT=1
  assert_service_case 1 "$all_calls"
  OPENUSAGE_EXIT=0
  AEROSPACE_EXIT=1
  assert_service_case 1 "openusage
aerospace
skhd"
  AEROSPACE_EXIT=0
  SKETCHYBAR_EXIT=1
  assert_service_case 1 "$all_calls"
  SKETCHYBAR_EXIT=0
  SKHD_EXIT=1
  assert_service_case 1 "$all_calls"

  for function_name in \
    preflight_setup accept_xcode_license install_homebrew install_brew_packages \
    link_dotfiles link_vscode_config install_nvm_node install_codex_cli \
    install_zinit install_zsh_plugins install_kitty install_sketchybar_assets \
    install_tmux_plugins install_yazi_flavor install_neovim_plugins; do
    eval "$function_name() { :; }"
  done
  restart_services() { return 1; }
  print_summary() { print -r -- summary >>"$SERVICE_FIXTURE_LOG"; }
  : >"$SERVICE_FIXTURE_LOG"
  if main --skip-system-defaults >/dev/null 2>&1; then
    printf "Setup main accepted a failed required-service postflight.\n" >&2
    exit 1
  fi
  [[ ! -s "$SERVICE_FIXTURE_LOG" ]]
' setup-services "$ROOT/setup.sh"

log "Checking Lua syntax"
while IFS= read -r file; do
  [[ -f "$file" ]] && luac -p "$file"
done < <(
  {
    git ls-files '*.lua'
    git ls-files --others --exclude-standard -- '*.lua'
    printf '%s\n' home/.config/sketchybar/sketchybarrc
  } | LC_ALL=C sort -u
)

log "Checking SketchyBar runtime behavior"
lua tests/sketchybar_runtime_spec.lua "$ROOT"

log "Checking Python syntax"
python3 - "$ROOT" <<'PY'
import ast
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
files = set()
for command in (
    ["git", "ls-files", "*.py"],
    ["git", "ls-files", "--others", "--exclude-standard", "--", "*.py"],
):
    files.update(subprocess.check_output(command, cwd=root, text=True).splitlines())
for name in sorted(files):
    path = root / name
    if path.is_file():
        ast.parse(path.read_text(), filename=name)
PY

log "Checking tmux session-manager behavior"
env "${ISOLATED_ENV[@]}" python3 - \
  "$ROOT/home/.config/tmux/scripts/session_manager.py" <<'PY'
import importlib.util
import sys
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("dotfiles_session_manager", path)
if spec is None or spec.loader is None:
    raise SystemExit(f"Could not import {path}")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

checks = (
    (module.sanitize_label("  research  ") == "research", "label trimming"),
    (module.sanitize_label("   ") == "session", "empty-label fallback"),
    (
        module.parse_optional_client(["--client", "client-1", "extra"])
        == ("client-1", ["extra"]),
        "optional client parsing",
    ),
)
for passed, description in checks:
    if not passed:
        raise SystemExit(f"tmux session-manager smoke failed: {description}")

sample = "\n".join(
    (
        "$2\t2-second\t200",
        "$3\tunindexed\t100",
        "$1\t1-first\t300",
    )
)
module.run_tmux = lambda args, check=True, capture=False: sample
sessions = module.list_sessions()
if [entry["id"] for entry in sessions] != ["$1", "$2", "$3"]:
    raise SystemExit("tmux session-manager smoke failed: session ordering")
if [entry["label"] for entry in sessions] != ["first", "second", "unindexed"]:
    raise SystemExit("tmux session-manager smoke failed: label parsing")

tmux_calls = []


def mock_refresh(args, check=True, capture=False):
    tmux_calls.append((args, check, capture))
    if args == ["list-clients", "-F", "#{client_name}"]:
        return "client-a\nclient-b"
    return ""


module.run_tmux = mock_refresh
module.refresh_clients()
expected_calls = [
    (["list-clients", "-F", "#{client_name}"], False, True),
    (["refresh-client", "-S", "-t", "client-a"], False, False),
    (["refresh-client", "-S", "-t", "client-b"], False, False),
]
if tmux_calls != expected_calls:
    raise SystemExit(
        f"tmux session-manager smoke failed: refresh routing: {tmux_calls!r}"
    )
PY

log "Checking TOML"
python3 - "$ROOT" <<'PY'
import subprocess
import sys
import tomllib
from pathlib import Path

root = Path(sys.argv[1])
files = set()
for command in (
    ["git", "ls-files", "*.toml"],
    ["git", "ls-files", "--others", "--exclude-standard", "--", "*.toml"],
):
    files.update(subprocess.check_output(command, cwd=root, text=True).splitlines())
for name in sorted(files):
    path = root / name
    if path.is_file():
        with path.open("rb") as handle:
            tomllib.load(handle)
PY

log "Checking JSON and JSONC"
while IFS= read -r file; do
  [[ -f "$file" ]] && json5 --validate "$file"
done < <(
  {
    git ls-files '*.json' '*.jsonc'
    git ls-files --others --exclude-standard -- '*.json' '*.jsonc'
  } | LC_ALL=C sort -u
)
jq empty home/.config/nvim/lazyvim.json
jq empty home/.config/nvim/lazy-lock.json
rg -Fq 'lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"' \
  home/.config/nvim/lua/config/lazy.lua

log "Checking Brewfile and LaunchAgent"
ruby -c Brewfile >/dev/null
plutil -lint home/Library/LaunchAgents/com.biboy.openusage.plist >/dev/null
brew_trust_targets="$(
  env "${ISOLATED_ENV[@]}" zsh -c \
    'source "$1"; declared_brew_trust_targets' zsh "$ROOT/setup.sh"
)"
[[ "$brew_trust_targets" == $'brew\tfelixkratz/formulae/sketchybar\nbrew\tasmvik/formulae/skhd\ncask\tnikitabobko/tap/aerospace' ]]
if rg -q 'brew trust --tap' setup.sh; then
  printf "Setup must trust declared Brew dependencies, not entire taps.\n" >&2
  exit 1
fi

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

object_output="$(env "${ISOLATED_ENV[@]}" \
  OPENUSAGE_FIXTURE_DIR="$fixture_root/object" AI_USAGE_BAR_DIR="$bar_root" \
  zsh home/.config/sketchybar/scripts/ai_usage.sh)"
array_output="$(env "${ISOLATED_ENV[@]}" \
  OPENUSAGE_FIXTURE_DIR="$fixture_root/array" AI_USAGE_BAR_DIR="$bar_root" \
  zsh home/.config/sketchybar/scripts/ai_usage.sh)"
empty_output="$(env "${ISOLATED_ENV[@]}" \
  OPENUSAGE_FIXTURE_DIR="$fixture_root/empty" AI_USAGE_BAR_DIR="$bar_root" \
  zsh home/.config/sketchybar/scripts/ai_usage.sh)"
malformed_output="$(env "${ISOLATED_ENV[@]}" \
  OPENUSAGE_FIXTURE_DIR="$fixture_root/malformed" AI_USAGE_BAR_DIR="$bar_root" \
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
  assert_bar "$object_output" "$provider"
  assert_bar "$array_output" "$provider"
  assert_bar "$empty_output" "$provider"
  assert_bar "$malformed_output" "$provider"
done

log "Checking generated-state boundaries"
[[ ! -e home/.config/tmux/plugins.lock ]]
[[ -z "$(find home/.codex/skills -type f -print -quit 2>/dev/null)" ]]
rg -q 'use = "yazi-rs/flavors:catppuccin-mocha"' home/.config/yazi/package.toml

log "Checking tmux plugin manifest"
[[ -f home/.config/tmux/plugins.conf && ! -e home/.config/tmux/plugins.txt ]]
rg -Fxq 'source-file ~/.config/tmux/plugins.conf' home/.tmux.conf
if rg -q '^[[:space:]]*set -g @plugin' home/.tmux.conf; then
  printf "tmux plugins must be declared only in plugins.conf.\n" >&2
  exit 1
fi
rg -Fq 'home/.config/tmux/plugins.conf' setup.sh
python3 - home/.config/tmux/plugins.conf <<'PY'
import re
import sys
from pathlib import Path

manifest = Path(sys.argv[1])
pattern = re.compile(r"set -g @plugin '([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)'")
plugins = []
for line_number, raw_line in enumerate(manifest.read_text().splitlines(), start=1):
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    match = pattern.fullmatch(line)
    if match is None:
        raise SystemExit(f"{manifest}:{line_number}: invalid plugin declaration")
    plugins.append(match.group(1))

if not plugins:
    raise SystemExit(f"{manifest}: no plugins declared")
if len(plugins) != len(set(plugins)):
    raise SystemExit(f"{manifest}: duplicate plugin declaration")
basenames = [plugin.rsplit("/", 1)[1] for plugin in plugins]
if len(basenames) != len(set(basenames)):
    raise SystemExit(f"{manifest}: plugin install-directory collision")
if "tmux-plugins/tpm" not in plugins:
    raise SystemExit(f"{manifest}: tmux-plugins/tpm is required")
PY

log "Checking explicit Stow folding boundaries"
manifest_target_dirs="$(python3 - "$FOLDING_MANIFEST" <<'PY'
import sys
from pathlib import Path, PurePosixPath

manifest = Path(sys.argv[1])
entries = [
    line.strip()
    for line in manifest.read_text().splitlines()
    if line.strip() and not line.lstrip().startswith("#")
]
if not entries or len(entries) != len(set(entries)):
    raise SystemExit(f"{manifest}: entries must be non-empty and unique")
for entry in entries:
    path = PurePosixPath(entry)
    if path.is_absolute() or ".." in path.parts or str(path) != entry:
        raise SystemExit(f"{manifest}: unsafe target path: {entry}")
print(*entries, sep="\n")
PY
)"
setup_target_dirs="$(
  env "${ISOLATED_ENV[@]}" zsh -c \
    'source "$1"; stow_target_directories' zsh "$ROOT/setup.sh"
)"
[[ "$setup_target_dirs" == "$manifest_target_dirs" ]] || {
  printf "setup.sh does not consume the Stow folding manifest exactly.\n" >&2
  diff -u \
    <(printf '%s\n' "$manifest_target_dirs") \
    <(printf '%s\n' "$setup_target_dirs") >&2 || true
  exit 1
}

log "Checking home package source boundaries"
boundary_failed=0
empty_package_dirs="$(find home -type d -empty -print | LC_ALL=C sort)"
if [[ -n "$empty_package_dirs" ]]; then
  printf "Empty directories found in the home package:\n%s\n" \
    "$empty_package_dirs" >&2
  boundary_failed=1
fi

git archive --format=tar HEAD | tar -xf - -C "$HEAD_ARCHIVE_ROOT"

untracked_package_paths="$({
  git ls-files --others --directory --exclude-standard -- \
    home stow-target-dirs.txt
  git ls-files --others --ignored --directory --exclude-standard -- home
} | LC_ALL=C sort -u)"
if [[ -n "$untracked_package_paths" ]]; then
  printf "  Temporary Git snapshot includes untracked package paths:\n%s\n" \
    "$untracked_package_paths"
fi

candidate_head_changes="$(
  snapshot_git diff --cached --name-status --no-renames HEAD -- \
    home stow-target-dirs.txt
)"
if [[ -n "$candidate_head_changes" ]]; then
  printf "  Candidate package content differs from HEAD:\n%s\n" \
    "$candidate_head_changes"
fi

worktree_target="$CHECK_WORK_DIR/stow-worktree-home"
candidate_target="$CHECK_WORK_DIR/stow-candidate-home"
head_target="$CHECK_WORK_DIR/stow-head-home"
mkdir -p "$worktree_target" "$candidate_target" "$head_target"
create_stow_target "$worktree_target"
create_stow_target "$candidate_target"
create_stow_target "$head_target"

worktree_plan="$CHECK_WORK_DIR/stow-worktree.plan"
candidate_plan="$CHECK_WORK_DIR/stow-candidate.plan"
head_plan="$CHECK_WORK_DIR/stow-head.plan"
worktree_leaf_plan="$CHECK_WORK_DIR/stow-worktree-leaf.plan"
candidate_leaf_plan="$CHECK_WORK_DIR/stow-candidate-leaf.plan"
write_stow_plan "$ROOT" "$worktree_target" "$worktree_plan"
write_stow_plan "$CANDIDATE_ROOT" "$candidate_target" "$candidate_plan"
write_stow_plan "$HEAD_ARCHIVE_ROOT" "$head_target" "$head_plan"
write_stow_plan "$ROOT" "$worktree_target" "$worktree_leaf_plan" \
  --no-folding
write_stow_plan \
  "$CANDIDATE_ROOT" "$candidate_target" "$candidate_leaf_plan" \
  --no-folding

ignored_target="$CHECK_WORK_DIR/stow-ignored-home"
ignored_plan="$CHECK_WORK_DIR/stow-ignored.plan"
mkdir -p \
  "$CANDIDATE_ROOT/home/.config/raycast/ai" \
  "$CANDIDATE_ROOT/home/.config/yazi/flavors/test.yazi" \
  "$CANDIDATE_ROOT/home/.config/zed/prompts" \
  "$CANDIDATE_ROOT/home/.config/zed/themes" \
  "$CANDIDATE_ROOT/home/.codex/skills/test"
: >"$CANDIDATE_ROOT/home/.config/raycast/ai/generated.json"
: >"$CANDIDATE_ROOT/home/.config/yazi/flavors/test.yazi/flavor.toml"
: >"$CANDIDATE_ROOT/home/.config/zed/prompts/generated.json"
: >"$CANDIDATE_ROOT/home/.config/zed/themes/generated.json"
: >"$CANDIDATE_ROOT/home/.codex/config.toml"
: >"$CANDIDATE_ROOT/home/.codex/skills/test/SKILL.md"
mkdir -p "$ignored_target"
create_stow_target "$ignored_target"
write_stow_plan "$CANDIDATE_ROOT" "$ignored_target" "$ignored_plan" \
  --no-folding
if ! cmp -s "$candidate_leaf_plan" "$ignored_plan"; then
  printf "Stow local-ignore rules expose generated fixture paths:\n" >&2
  diff -u "$candidate_leaf_plan" "$ignored_plan" >&2 || true
  boundary_failed=1
fi

if ! cmp -s "$worktree_plan" "$candidate_plan"; then
  printf "Worktree Stow plan differs from the temporary Git-index plan:\n" >&2
  diff -u "$candidate_plan" "$worktree_plan" >&2 || true
  boundary_failed=1
fi

if ! cmp -s "$worktree_leaf_plan" "$candidate_leaf_plan"; then
  printf "Worktree has Stow-visible paths absent from its Git snapshot:\n" >&2
  diff -u "$candidate_leaf_plan" "$worktree_leaf_plan" >&2 || true
  boundary_failed=1
fi

if ! cmp -s "$candidate_plan" "$head_plan"; then
  printf "  Candidate Stow plan differs from the HEAD archive plan:\n"
  diff -u "$head_plan" "$candidate_plan" || true
fi

while IFS= read -r target_dir; do
  [[ -n "$target_dir" ]] || continue
  if grep -Fxq "LINK $target_dir" "$worktree_plan"; then
    printf "Stow folded a protected target directory: %s\n" "$target_dir" >&2
    boundary_failed=1
  fi
done <<<"$manifest_target_dirs"

if grep -Fq '.stow-local-ignore' "$worktree_plan"; then
  printf "Stow attempted to deploy its package-local ignore file.\n" >&2
  boundary_failed=1
fi

(( boundary_failed == 0 )) || exit 1

create_stow_target "$ISOLATED_HOME"
(
  cd "$ISOLATED_TMP"
  env HOME="$STOW_CONFIG_HOME" LC_ALL=C \
    stow --dir="$ROOT" --target="$ISOLATED_HOME" home
)

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

log "Checking patch whitespace"
snapshot_git diff --cached --check HEAD -- :/

if (( RUN_LIVE_CHECKS )); then
  for command in aerospace brew fc-match fc-scan nvim tmux tree-sitter; do
    require "$command"
  done

  log "Checking installed Kitty font faces"
  python3 - home/.config/kitty/kitty.conf <<'PY'
import shlex
import subprocess
import sys
from pathlib import Path

FACE_KEYS = ("font_family", "bold_font", "italic_font", "bold_italic_font")
MATCH_FORMAT = "%{file}\t%{index}\t%{postscriptname}\t%{family}\n"
SCAN_FORMAT = "%{index}\t%{postscriptname}\t%{family}\n"


def aliases(value: str) -> set[str]:
    return {item.strip() for item in value.split(",") if item.strip()}


def run(command: list[str]) -> str:
    result = subprocess.run(command, check=True, text=True, capture_output=True)
    return result.stdout


def font_match(pattern: str) -> tuple[str, str, str, str]:
    line = run(["fc-match", "-f", MATCH_FORMAT, pattern]).splitlines()[0]
    fields = line.split("\t")
    if len(fields) != 4 or not fields[0]:
        raise SystemExit(f"fontconfig returned an invalid match for {pattern!r}")
    return fields[0], fields[1], fields[2], fields[3]


def scan_confirms(
    file_name: str, index: str, expected: str, field_number: int
) -> bool:
    for line in run(["fc-scan", "-f", SCAN_FORMAT, file_name]).splitlines():
        fields = line.split("\t")
        if len(fields) == 3 and fields[0] == index:
            values = aliases(fields[field_number])
            if expected in values:
                return True
    return False


def require_postscript_name(name: str) -> bool:
    file_name, index, postscript_names, _ = font_match(f":postscriptname={name}")
    if name not in aliases(postscript_names):
        return False
    if not scan_confirms(file_name, index, name, 1):
        raise SystemExit(f"fc-scan did not confirm PostScript face {name!r}")
    return True


def require_family(name: str) -> None:
    file_name, index, _, families = font_match(name)
    if name not in aliases(families):
        raise SystemExit(f"fontconfig fell back while resolving family {name!r}")
    if not scan_confirms(file_name, index, name, 2):
        raise SystemExit(f"fc-scan did not confirm font family {name!r}")


faces: dict[str, str] = {}
symbol_families: set[str] = set()
for raw_line in Path(sys.argv[1]).read_text().splitlines():
    tokens = shlex.split(raw_line, comments=True)
    if not tokens:
        continue
    if tokens[0] in FACE_KEYS:
        faces[tokens[0]] = " ".join(tokens[1:])
    elif tokens[0] == "symbol_map" and len(tokens) >= 3:
        symbol_families.add(" ".join(tokens[2:]))

missing = [key for key in FACE_KEYS if not faces.get(key)]
if missing:
    raise SystemExit(f"Kitty font settings are missing: {', '.join(missing)}")

for key in FACE_KEYS:
    configured = faces[key]
    if configured.startswith("postscript_name="):
        postscript_name = configured.removeprefix("postscript_name=")
        if not require_postscript_name(postscript_name):
            raise SystemExit(f"Missing PostScript face for {key}: {postscript_name}")
    else:
        require_family(configured)

if not symbol_families:
    raise SystemExit("Kitty configuration has no symbol_map families")
for family in sorted(symbol_families):
    require_family(family)
PY

  log "Checking installed Neovim Tree-sitter runtime"
  tree_sitter_output="$(tree-sitter --version)"
  if [[ "$tree_sitter_output" =~ '([0-9]+([.][0-9]+){2})' ]]; then
    tree_sitter_version="$match[1]"
  else
    printf "Could not parse tree-sitter version: %s\n" \
      "$tree_sitter_output" >&2
    exit 1
  fi
  minimum_tree_sitter_version="0.26.1"
  autoload -Uz is-at-least
  is-at-least "$minimum_tree_sitter_version" "$tree_sitter_version" || {
    printf "tree-sitter %s is below required %s.\n" \
      "$tree_sitter_version" "$minimum_tree_sitter_version" >&2
    exit 1
  }
  treesitter_root="$INSTALLED_XDG_DATA_HOME/nvim/lazy/nvim-treesitter"
  [[ -f "$treesitter_root/plugin/filetypes.lua" ]] || {
    printf "nvim-treesitter is not installed at %s.\n" \
      "$treesitter_root" >&2
    exit 1
  }
  if ! treesitter_status="$(
    GIT_OPTIONAL_LOCKS=0 \
      git -C "$treesitter_root" status --porcelain --untracked-files=no 2>&1
  )"; then
    printf "Could not inspect installed nvim-treesitter: %s\n" \
      "$treesitter_status" >&2
    exit 1
  fi
  [[ -z "$treesitter_status" ]] || {
    printf "Installed nvim-treesitter checkout is dirty:\n%s\n" \
      "$treesitter_status" >&2
    exit 1
  }
  expected_treesitter_commit="$(
    jq -er '.["nvim-treesitter"].commit' home/.config/nvim/lazy-lock.json
  )"
  installed_treesitter_commit="$(git -C "$treesitter_root" rev-parse HEAD)"
  [[ "$installed_treesitter_commit" == "$expected_treesitter_commit" ]] || {
    printf "Installed nvim-treesitter does not match lazy-lock.json.\n" >&2
    exit 1
  }
  env "${ISOLATED_ENV[@]}" \
    XDG_DATA_HOME="$INSTALLED_XDG_DATA_HOME" \
    NVIM_TS_ROOT="$treesitter_root" \
    NVIM_LOG_FILE="$CHECK_WORK_DIR/nvim.log" \
    nvim --headless -u NONE --noplugin -l - <<'LUA'
local root = assert(vim.env.NVIM_TS_ROOT)
vim.opt.runtimepath:append(root .. "/runtime")
dofile(root .. "/plugin/filetypes.lua")
for _, filetype in ipairs({ "diff", "vim", "lua", "jsonc" }) do
  local language = vim.treesitter.language.get_lang(filetype) or filetype
  vim.treesitter.language.add(language)
  assert(
    vim.treesitter.query.get(language, "highlights"),
    ("missing highlights query for %s (%s)"):format(filetype, language)
  )
end
LUA

  log "Checking live AeroSpace configuration"
  aerospace_source="$ROOT/home/.config/aerospace/aerospace.toml"
  if ! active_aerospace_config="$(aerospace config --config-path)"; then
    printf "AeroSpace server is unavailable or inaccessible.\n" >&2
    exit 1
  fi
  [[ -r "$active_aerospace_config" ]] || {
    printf "Active AeroSpace config is not readable: %s\n" \
      "$active_aerospace_config" >&2
    exit 1
  }
  cmp -s "$aerospace_source" "$active_aerospace_config" || {
    printf "Active AeroSpace config differs from the repository source: %s\n" \
      "$active_aerospace_config" >&2
    exit 1
  }
  aerospace reload-config --dry-run --warnings-as-errors --no-gui

  log "Checking tmux configuration in an isolated live server"
  installed_tmux_plugins="$HOME/.tmux/plugins"
  [[ -x "$installed_tmux_plugins/tpm/tpm" ]] || {
    printf "Installed TPM checkout is missing or not executable: %s\n" \
      "$installed_tmux_plugins/tpm/tpm" >&2
    exit 1
  }
  mkdir -p "$ISOLATED_HOME/.tmux"
  ln -s "$installed_tmux_plugins" "$ISOLATED_HOME/.tmux/plugins"
  tmux_config_output="$CHECK_WORK_DIR/tmux-config.out"
  if ! env "${ISOLATED_ENV[@]}" tmux -S "$TMUX_SOCKET" \
    -f /dev/null \
    new-session -d -s dotfiles-check /usr/bin/tail -f /dev/null \
    >"$tmux_config_output" 2>&1; then
    sed 's/^/  /' "$tmux_config_output" >&2
    env "${ISOLATED_ENV[@]}" tmux -S "$TMUX_SOCKET" \
      kill-server >/dev/null 2>&1 || true
    exit 1
  fi
  TMUX_STARTED=1
  if ! env "${ISOLATED_ENV[@]}" tmux -S "$TMUX_SOCKET" \
    source-file "$ISOLATED_HOME/.tmux.conf" \
    >>"$tmux_config_output" 2>&1; then
    printf "tmux rejected the configuration:\n" >&2
    sed 's/^/  /' "$tmux_config_output" >&2
    exit 1
  fi
  [[ ! -s "$tmux_config_output" ]] || {
    printf "tmux reported configuration diagnostics:\n" >&2
    sed 's/^/  /' "$tmux_config_output" >&2
    exit 1
  }
  for _ in {1..20}; do
    session_name="$(env "${ISOLATED_ENV[@]}" tmux -S "$TMUX_SOCKET" \
      display-message -p '#{session_name}')"
    [[ "$session_name" == "1-dotfiles-check" ]] && break
    sleep 0.05
  done
  [[ "$session_name" == "1-dotfiles-check" ]] || {
    printf "tmux session hook did not normalize the session name: %s\n" \
      "$session_name" >&2
    exit 1
  }
  env "${ISOLATED_ENV[@]}" tmux -S "$TMUX_SOCKET" \
    show-options -g status-interval >/dev/null
  env "${ISOLATED_ENV[@]}" tmux -S "$TMUX_SOCKET" \
    list-keys -T root >/dev/null
  for hook_name in client-attached client-resized client-session-changed; do
    hook_value="$(
      env "${ISOLATED_ENV[@]}" tmux -S "$TMUX_SOCKET" \
        show-hooks -g "$hook_name"
    )"
    grep -Fq 'refresh-client -S' <<<"$hook_value"
    if grep -Fq 'run-shell' <<<"$hook_value"; then
      printf "tmux hook %s must refresh in direct client context.\n" \
        "$hook_name" >&2
      exit 1
    fi
  done
  env "${ISOLATED_ENV[@]}" tmux -S "$TMUX_SOCKET" kill-server
  TMUX_STARTED=0

  source "$ROOT/lib/brew_bundle.zsh"
  export HOMEBREW_NO_AUTO_UPDATE=1

  log "Checking live Brew bundle state"
  bundle_cask_skip="$(brew_bundle_cask_skip)"
  HOMEBREW_BUNDLE_CASK_SKIP="$bundle_cask_skip" \
    brew bundle check --file="$ROOT/Brewfile" --verbose

  log "Reporting unmanaged Brew dependencies"
  brew_bundle_report_extras "$ROOT/Brewfile"
else
  printf "  Live font, Neovim, AeroSpace, tmux, and Homebrew checks skipped; rerun with --live.\n"
fi

final_worktree_changes="$(
  snapshot_git diff --name-status --no-ext-diff -- :/
)"
final_untracked_paths="$(
  snapshot_git ls-files --others --exclude-standard -- :/
)"
if [[ -n "$final_worktree_changes" || -n "$final_untracked_paths" ]]; then
  printf "Worktree changed after the temporary Git snapshot was created:\n%s\n" \
    "$final_worktree_changes${final_worktree_changes:+$'\n'}$final_untracked_paths" \
    >&2
  exit 1
fi

final_worktree_leaf_plan="$CHECK_WORK_DIR/stow-worktree-final-leaf.plan"
write_stow_plan \
  "$ROOT" "$worktree_target" "$final_worktree_leaf_plan" --no-folding
if ! cmp -s "$candidate_leaf_plan" "$final_worktree_leaf_plan"; then
  printf "Stow-visible worktree paths changed while checks were running:\n" >&2
  diff -u "$candidate_leaf_plan" "$final_worktree_leaf_plan" >&2 || true
  exit 1
fi

cmp -s "$real_git_index" "$REAL_GIT_INDEX_SNAPSHOT" || {
  printf "The real Git index changed while checks were running.\n" >&2
  exit 1
}

printf "All checks passed.\n"
