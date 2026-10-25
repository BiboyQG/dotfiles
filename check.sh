#!/usr/bin/env zsh
set -euo pipefail

unset GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
# The Python specs check their results with assert, which PYTHONOPTIMIZE
# strips; run them with the option off whatever the caller's environment.
unset PYTHONOPTIMIZE

ROOT="${0:A:h}"
cd "$ROOT"

RUN_LIVE_CHECKS=0
BREW_AUDIT_INCOMPLETE=0
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
  "$TEMP_GIT_OBJECTS"

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
  rm -rf -- "$CHECK_WORK_DIR"
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

create_stow_target() {
  mkdir -p -- "$1"/${^${(f)manifest_target_dirs}}
}

write_stow_plan() {
  local source_root="$1"
  local target_root="$2"
  local output_file="$3"

  (
    cd "$ISOLATED_TMP"
    env HOME="$STOW_CONFIG_HOME" LC_ALL=C stow \
      --dir="$source_root" --simulate --verbose=2 --no-folding \
      --target="$target_root" home
  ) 2>&1 \
    | sed -nE \
      -e 's/^[[:space:]]*LINK: (.*) => .*/LINK \1/p' \
      -e 's/^[[:space:]]*MKDIR: (.*)$/MKDIR \1/p' \
    | LC_ALL=C sort >"$output_file"
}

# Tracked plus untracked (not ignored) repository files matching the pathspecs.
repo_files() {
  git ls-files -co --exclude-standard -- "$@"
}

for command in json5 lua luac magick rg stow tmux; do
  require "$command"
done

[[ -z "$(git ls-files --unmerged)" ]] || {
  printf "Cannot snapshot a Git index with unresolved merges.\n" >&2
  exit 1
}
real_git_index="$(git rev-parse --path-format=absolute --git-path index)"
real_git_objects="$(git rev-parse --path-format=absolute --git-path objects)"
cp "$real_git_index" "$TEMP_GIT_INDEX"
cp "$real_git_index" "$REAL_GIT_INDEX_SNAPSHOT"
SNAPSHOT_GIT_ENV=(
  "GIT_INDEX_FILE=$TEMP_GIT_INDEX"
  "GIT_OBJECT_DIRECTORY=$TEMP_GIT_OBJECTS"
  "GIT_ALTERNATE_OBJECT_DIRECTORIES=$real_git_objects"
)
snapshot_git() {
  env "${SNAPSHOT_GIT_ENV[@]}" git "$@"
}
snapshot_git add -A -- :/
snapshot_git ls-files --error-unmatch -- stow-target-dirs.txt >/dev/null
snapshot_git checkout-index --all --prefix="$CANDIDATE_ROOT/"

log "Checking shell syntax"
for file in setup.sh check.sh lib/*.zsh home/.p10k.zsh home/.zprofile home/.zshrc \
  home/.config/aerospace/scripts/resize-edge \
  home/.config/sketchybar/scripts/ai_usage.sh \
  home/.config/sketchybar/scripts/media_state.sh; do
  zsh -n "$file"
done
for file in \
  home/bin/abs \
  home/bin/ip \
  home/.config/tmux/scripts/*.sh \
  home/.config/tmux/tmux-status/*.sh; do
  /bin/bash -n "$file"
done

log "Checking public IP helper behavior"
IP_FIXTURE_DIR="$CHECK_WORK_DIR/ip-fixtures"
IP_SLOW_MARKER="$IP_FIXTURE_DIR/slow-started"
mkdir -p "$IP_FIXTURE_DIR"

cat >"$IP_FIXTURE_DIR/curl" <<'BASH'
#!/bin/bash
set -euo pipefail

[[ "$#" -eq 5 ]]
[[ "$1" == "-4" && "$2" == "-f" ]]
[[ "$3" == "--max-time" && "$4" == "2" ]]
url="$5"
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
  partial_primary_fallback:https://api.ipify.org)
    printf '203.0.113.7'
    exit 18
    ;;
  partial_primary_fallback:https://ipv4.icanhazip.com)
    printf '203.0.113.70\n'
    ;;
  partial_primary_fallback:*)
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
  all_fail:* | partial_dig:* | successful_dig:*)
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
case "$IP_MOCK_SCENARIO" in
  partial_dig)
    printf '203.0.113.7\n'
    ;;
  successful_dig)
    printf '198.51.100.18\n'
    exit 0
    ;;
esac
exit 9
BASH
chmod +x "$IP_FIXTURE_DIR/curl" "$IP_FIXTURE_DIR/dig"

run_ip_case() {
  local scenario="$1"
  local interpreter="$2"

  IP_CASE_CURL_LOG="$IP_FIXTURE_DIR/$scenario.curl.log"
  IP_CASE_DIG_LOG="$IP_FIXTURE_DIR/$scenario.dig.log"
  IP_CASE_STDERR="$IP_FIXTURE_DIR/$scenario.stderr"
  : >"$IP_CASE_CURL_LOG"
  : >"$IP_CASE_DIG_LOG"
  rm -f -- "$IP_SLOW_MARKER"

  IP_CASE_EXIT=0
  IP_CASE_OUTPUT="$(
    env "${ISOLATED_ENV[@]}" \
      PATH="$IP_FIXTURE_DIR:$PATH" \
      IP_MOCK_SCENARIO="$scenario" \
      IP_CURL_LOG="$IP_CASE_CURL_LOG" \
      IP_DIG_LOG="$IP_CASE_DIG_LOG" \
      IP_SLOW_MARKER="$IP_SLOW_MARKER" \
      "$interpreter" "$ROOT/home/bin/ip" 2>"$IP_CASE_STDERR"
  )" || IP_CASE_EXIT=$?
}

zmodload zsh/datetime
# The shebang resolves to whichever bash is first on PATH, so exercise both the
# macOS baseline and the Homebrew build when they differ.
typeset -Ua ip_interpreters
ip_interpreters=(/bin/bash "$(command -v bash)")
for ip_interpreter in "${ip_interpreters[@]}"; do
  run_ip_case primary_success "$ip_interpreter"
  (( IP_CASE_EXIT == 0 ))
  [[ "$IP_CASE_OUTPUT" == "203.0.113.7" ]]
  [[ ! -s "$IP_CASE_STDERR" ]]
  [[ "$(<"$IP_CASE_CURL_LOG")" == "https://api.ipify.org" ]]
  [[ ! -s "$IP_CASE_DIG_LOG" ]]

  run_ip_case invalid_primary_fallback "$ip_interpreter"
  (( IP_CASE_EXIT == 0 ))
  [[ "$IP_CASE_OUTPUT" == "198.51.100.17" ]]
  [[ ! -s "$IP_CASE_STDERR" ]]
  grep -Fxq 'https://api.ipify.org' "$IP_CASE_CURL_LOG"
  [[ ! -s "$IP_CASE_DIG_LOG" ]]

  run_ip_case partial_primary_fallback "$ip_interpreter"
  (( IP_CASE_EXIT == 0 ))
  [[ "$IP_CASE_OUTPUT" == "203.0.113.70" ]]
  [[ ! -s "$IP_CASE_STDERR" ]]
  [[ ! -s "$IP_CASE_DIG_LOG" ]]

  run_ip_case partial_dig "$ip_interpreter"
  (( IP_CASE_EXIT == 1 ))
  [[ -z "$IP_CASE_OUTPUT" ]]
  [[ "$(<"$IP_CASE_STDERR")" == "unable to determine public IPv4" ]]
  [[ -s "$IP_CASE_DIG_LOG" ]]

  run_ip_case successful_dig "$ip_interpreter"
  (( IP_CASE_EXIT == 0 ))
  [[ "$IP_CASE_OUTPUT" == "198.51.100.18" ]]
  [[ ! -s "$IP_CASE_STDERR" ]]

  typeset -F race_started race_elapsed
  race_started=$EPOCHREALTIME
  run_ip_case race "$ip_interpreter"
  race_elapsed=$(( EPOCHREALTIME - race_started ))
  (( IP_CASE_EXIT == 0 ))
  [[ "$IP_CASE_OUTPUT" == "192.0.2.44" ]]
  [[ ! -s "$IP_CASE_STDERR" ]]
  (( race_elapsed < 3.0 )) || {
    printf "Public IP fallback waited %.3fs for a slow endpoint.\n" \
      "$race_elapsed" >&2
    exit 1
  }
  [[ ! -s "$IP_CASE_DIG_LOG" ]]

  run_ip_case all_fail "$ip_interpreter"
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
done

log "Checking media-state helper behavior"
media_cache="$CHECK_WORK_DIR/media-cache"
mkdir -p "$media_cache"
media_state() {
  env "${ISOLATED_ENV[@]}" zsh \
    home/.config/sketchybar/scripts/media_state.sh --stdin "$media_cache"
}
media_playing_json='{"title":"Fixture Song","artist":"Fixture Artist","playbackRate":1,"bundleIdentifier":"com.spotify.client","artworkData":"iVBORw0KGgo="}'
media_playing_output="$(media_state <<<"$media_playing_json")"
jq -e \
  --arg cache_prefix "$media_cache/media-artwork-" '
    .playing == true
      and .title == "Fixture Song"
      and .artist == "Fixture Artist"
      and (.artwork | startswith($cache_prefix))
  ' <<<"$media_playing_output" >/dev/null
media_artwork="$(jq -er '.artwork' <<<"$media_playing_output")"
[[ -s "$media_artwork" ]]

media_expired="$media_cache/media-artwork-expired-fixture"
media_recent="$media_cache/media-artwork-recent-fixture"
cp "$media_artwork" "$media_expired"
cp "$media_artwork" "$media_recent"
touch -t 200001010000 "$media_artwork" "$media_expired"
media_reused_output="$(media_state <<<"$media_playing_json")"
[[ "$(jq -er '.artwork' <<<"$media_reused_output")" == "$media_artwork" ]]
[[ -s "$media_artwork" && ! -e "$media_expired" && -s "$media_recent" ]]

media_stopped_output="$(media_state <<<'{"title":"Paused","playbackRate":0,"bundleIdentifier":"com.spotify.client"}')"
jq -e '. == {playing:false}' <<<"$media_stopped_output" >/dev/null

media_music_output="$(media_state <<<'{"title":"Music Fixture","artist":"Fixture Artist","playbackRate":1,"bundleIdentifier":"com.apple.Music"}')"
jq -e \
  '.playing == true and .title == "Music Fixture" and .artwork == ""' \
  <<<"$media_music_output" >/dev/null

media_unrelated_output="$(media_state <<<'{"title":"Browser Media","playbackRate":1,"bundleIdentifier":"com.google.Chrome","isMusicApp":true}')"
jq -e '. == {playing:false}' <<<"$media_unrelated_output" >/dev/null

media_malformed_output="$(media_state <<<'{invalid')"
jq -e '. == {playing:false}' <<<"$media_malformed_output" >/dev/null

media_invalid_artwork_output="$(media_state <<<'{"title":"Bad Art","playbackRate":1,"bundleIdentifier":"com.spotify.client","artworkData":"%%%"}')"
jq -e \
  '.playing == true and .title == "Bad Art" and .artwork == ""' \
  <<<"$media_invalid_artwork_output" >/dev/null
[[ -z "$(find "$media_cache" -type f -name 'media-artwork.??????' -print -quit)" ]]

log "Checking tmux attach helper"
ta_function="$(sed -n '/^function ta {$/,/^}$/p' home/.zshrc)"
TA_FIXTURE_LOG="$CHECK_WORK_DIR/ta-calls.log"
TA_FIXTURE_STDERR="$CHECK_WORK_DIR/ta-stderr.log"
# From a plain shell the helper attaches; inside tmux, which refuses nested
# attach, it switches the client and rejects attach-only options such as -d.
# Bare and option-only calls always attach.
for ta_case in outside inside; do
  : >"$TA_FIXTURE_LOG"
  env "${ISOLATED_ENV[@]}" TA_FIXTURE_LOG="$TA_FIXTURE_LOG" TA_CASE="$ta_case" \
    zsh -fc '
      eval "$1"
      tmux() {
        if [[ "$1" == list-sessions ]]; then
          printf "%s\n" "\$3:::1-dot" "\$7:::2-spreadsheet-build"
          return 0
        fi
        print -r -- "tmux $*" >>"$TA_FIXTURE_LOG"
      }
      [[ "$TA_CASE" == inside ]] && TMUX=fixture-socket,1,0
      ta
      ta -d
      ta dot
      ta 2 -d
      ta spreadsheet-build
      ta missing
    ' ta-fixture "$ta_function" 2>"$TA_FIXTURE_STDERR"
  case "$ta_case" in
    outside)
      ta_expected="tmux attach
tmux attach -d
tmux attach -t \$3
tmux attach -t \$7 -d
tmux attach -t \$7
tmux attach -t missing"
      [[ ! -s "$TA_FIXTURE_STDERR" ]]
      ;;
    inside)
      ta_expected="tmux attach
tmux attach -d
tmux switch-client -t \$3
tmux switch-client -t \$7
tmux switch-client -t missing"
      grep -Fxq 'ta: attach options are not supported inside tmux: -d' \
        "$TA_FIXTURE_STDERR"
      ;;
  esac
  [[ "$(<"$TA_FIXTURE_LOG")" == "$ta_expected" ]] || {
    printf "ta ran the wrong tmux commands %s tmux:\n" "$ta_case" >&2
    sed 's/^/  /' "$TA_FIXTURE_LOG" >&2
    exit 1
  }
done

log "Checking setup command-line behavior"
setup_help="$(env "${ISOLATED_ENV[@]}" zsh setup.sh --help)"
grep -Fq 'usage:' <<<"$setup_help"
grep -Fq -- '--update' <<<"$setup_help"
setup_status=0
env "${ISOLATED_ENV[@]}" zsh setup.sh --invalid-check-option >/dev/null 2>&1 || setup_status=$?
(( setup_status == 2 )) || {
  printf "setup.sh returned %d for an invalid option; expected 2.\n" "$setup_status" >&2
  exit 1
}

[[ "$(tail -n 3 setup.sh)" == 'if [[ "${ZSH_EVAL_CONTEXT:-}" == toplevel ]]; then
  main "$@"
fi' ]] || {
  printf "setup.sh must keep main behind its source-safe entry guard\n" >&2
  exit 1
}

log "Checking setup preflight isolation and conflict behavior"
SETUP_FIXTURE_ROOT="$CHECK_WORK_DIR/setup-preflight"
SETUP_FIXTURE_SOURCE="$SETUP_FIXTURE_ROOT/source"
SETUP_FIXTURE_HOME="$SETUP_FIXTURE_ROOT/home"
SETUP_FIXTURE_TMP="$SETUP_FIXTURE_ROOT/tmp"
SETUP_SNAPSHOT_DIR="$CHECK_WORK_DIR/setup-snapshots"
SETUP_POISON_MARKER="$SETUP_SNAPSHOT_DIR/poison"
mkdir -p \
  "$SETUP_FIXTURE_SOURCE/home/.claude" \
  "$SETUP_FIXTURE_SOURCE/home/.codex" \
  "$SETUP_FIXTURE_SOURCE/home/.config/kitty" \
  "$SETUP_FIXTURE_SOURCE/home/.config/nvim" \
  "$SETUP_FIXTURE_SOURCE/home/.config/yazi" \
  "$SETUP_FIXTURE_SOURCE/home/.config/preflight-boundary" \
  "$SETUP_FIXTURE_SOURCE/home/Library/Application Support/Code/User" \
  "$SETUP_FIXTURE_SOURCE/home/Library/LaunchAgents" \
  "$SETUP_FIXTURE_HOME/.config/preflight-boundary" \
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
    print(
        relative,
        kind,
        mode,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_flags,
        metadata.st_mtime_ns,
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
    zsh -fc '
      cd "$6"
      source "$1"
      DOTFILES_DIR="${2:A}"
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
        if [[ "$PWD" != "$STOW_CONFIG_CWD" || "$HOME" != "$STOW_CONFIG_HOME" ]]; then
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
      killall() { poison killall; }
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

assert_setup_preflight() {
  local name="$1"
  local expectation="$2"
  shift 2
  local -a patterns=()
  while (( $# )) && [[ "$1" != -- ]]; do
    patterns+=("$1")
    shift
  done
  (( $# )) && shift
  local before="$SETUP_SNAPSHOT_DIR/$name.before"
  local after="$SETUP_SNAPSHOT_DIR/$name.after"
  local output="$SETUP_SNAPSHOT_DIR/$name.out"
  local exit_status=0 pattern

  write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$before"
  run_setup_preflight "$output" "$@" || exit_status=$?
  if [[ "$expectation" == accept ]] && (( exit_status != 0 )); then
    printf "Setup preflight fixture %s failed:\n" "$name" >&2
    sed 's/^/  /' "$output" >&2
    exit 1
  fi
  if [[ "$expectation" == reject ]] && (( exit_status == 0 )); then
    printf "Setup preflight fixture %s was accepted.\n" "$name" >&2
    exit 1
  fi
  for pattern in "${patterns[@]}"; do
    grep -Fq -- "$pattern" "$output" || {
      printf "Setup preflight fixture %s is missing output: %s\n" "$name" "$pattern" >&2
      exit 1
    }
  done
  write_tree_snapshot "$SETUP_FIXTURE_ROOT" >"$after"
  cmp -s "$before" "$after" || {
    printf "Setup preflight fixture %s mutated its target:\n" "$name" >&2
    diff -u "$before" "$after" >&2 || true
    exit 1
  }
  [[ ! -e "$SETUP_POISON_MARKER" ]] || {
    printf "Setup preflight fixture %s ran a poisoned command.\n" "$name" >&2
    exit 1
  }
}

assert_setup_preflight clean accept

mkdir -p "$SETUP_FIXTURE_SOURCE/home/.config/yazi/flavors"
ln -s "$SETUP_FIXTURE_SOURCE/home/.config/yazi" \
  "$SETUP_FIXTURE_HOME/.config/yazi"
assert_setup_preflight folded reject \
  "Ignored machine-local data would be stranded by Stow migration: $SETUP_FIXTURE_SOURCE/home/.config/yazi/flavors"
rm -- "$SETUP_FIXTURE_HOME/.config/yazi"
rmdir "$SETUP_FIXTURE_SOURCE/home/.config/yazi/flavors"

# Entries below a folded sub-directory stay reachable through its link, and
# a Finder .DS_Store is not machine-local data, so neither blocks migration.
mkdir -p "$SETUP_FIXTURE_SOURCE/home/.config/yazi/plugins"
: >"$SETUP_FIXTURE_SOURCE/home/.config/yazi/plugins/.gitignore"
: >"$SETUP_FIXTURE_SOURCE/home/.config/yazi/.DS_Store"
ln -s "$SETUP_FIXTURE_SOURCE/home/.config/yazi" \
  "$SETUP_FIXTURE_HOME/.config/yazi"
assert_setup_preflight folded-reachable accept
rm -- "$SETUP_FIXTURE_HOME/.config/yazi" \
  "$SETUP_FIXTURE_SOURCE/home/.config/yazi/plugins/.gitignore" \
  "$SETUP_FIXTURE_SOURCE/home/.config/yazi/.DS_Store"
rmdir "$SETUP_FIXTURE_SOURCE/home/.config/yazi/plugins"

mkdir -p "$SETUP_FIXTURE_HOME/.config/kitty"
printf 'foreign managed state\n' \
  >"$SETUP_FIXTURE_HOME/.config/kitty/kitty.conf"
assert_setup_preflight conflict reject \
  "Stow conflict: $SETUP_FIXTURE_HOME/.config/kitty/kitty.conf already exists."

assert_setup_preflight stow-real reject \
  '../source/home/.config/kitty/kitty.conf' '--adopt not specified' \
  -- stow-real-conflict

corrupt_checkout="$SETUP_FIXTURE_HOME/.nvm"
mkdir -p "$corrupt_checkout/.git/objects"
printf 'not-a-valid-head\n' >"$corrupt_checkout/.git/HEAD"
assert_setup_preflight corrupt-git reject \
  "Could not inspect Git checkout $corrupt_checkout:" \
  -- git-checkout "$corrupt_checkout"

wrong_origin_checkout="$SETUP_FIXTURE_HOME/wrong-nvm"
git init --quiet "$wrong_origin_checkout"
git -C "$wrong_origin_checkout" remote add origin \
  https://github.com/example/not-nvm.git
assert_setup_preflight wrong-origin reject \
  "Unexpected origin for Git checkout nvm-sh/nvm at $wrong_origin_checkout: https://github.com/example/not-nvm.git" \
  -- github-checkout "$wrong_origin_checkout"

printf '../escape\n' >>"$SETUP_FIXTURE_SOURCE/stow-target-dirs.txt"
assert_setup_preflight invalid reject 'Invalid Stow target directory: ../escape'

log "Checking setup NVM activation"
NVM_FIXTURE_HOME="$SETUP_SNAPSHOT_DIR/nvm-home"
NVM_FIXTURE_BIN="$NVM_FIXTURE_HOME/.nvm/versions/node/v1.2.3/bin"
NVM_FIXTURE_LOG="$NVM_FIXTURE_HOME/nvm-calls.log"
BREW_FIXTURE_BIN="$SETUP_SNAPSHOT_DIR/homebrew/bin"
mkdir -p "$NVM_FIXTURE_HOME/.nvm" "$NVM_FIXTURE_BIN" "$BREW_FIXTURE_BIN"
printf '#!/bin/sh\nexit 0\n' >"$NVM_FIXTURE_BIN/npm"
printf '#!/bin/sh\nexit 0\n' >"$BREW_FIXTURE_BIN/npm"
chmod +x "$NVM_FIXTURE_BIN/npm" "$BREW_FIXTURE_BIN/npm"
cat >"$NVM_FIXTURE_HOME/.nvm/nvm.sh" <<'ZSH'
NVM_FIXTURE_INSTALLED=0
nvm() {
  local command="$1"
  local entry
  local -a updated_path

  case "$command" in
    install)
      NVM_FIXTURE_INSTALLED=1
      ;;
    alias)
      return 0
      ;;
    version)
      # Until install runs, the default alias still names the previous release
      # or, like the real nvm, prints N/A and fails when it does not exist.
      if [[ "$2" == default && "$NVM_FIXTURE_INSTALLED" == 0 ]]; then
        print -r -- "$NVM_FIXTURE_PREVIOUS"
        [[ "$NVM_FIXTURE_PREVIOUS" != N/A ]] || return 3
      else
        print -r -- v1.2.3
      fi
      ;;
    reinstall-packages | uninstall)
      print -r -- "$command $2" >>"$NVM_FIXTURE_LOG"
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
# The previous default is migrated and removed only when it is a different,
# existing version; a matching or missing default must leave nvm alone.
for nvm_previous in v1.0.0 v1.2.3 N/A; do
  : >"$NVM_FIXTURE_LOG"
  env \
    HOME="$NVM_FIXTURE_HOME" \
    NVM_FIXTURE_BIN="$NVM_FIXTURE_BIN" \
    NVM_FIXTURE_LOG="$NVM_FIXTURE_LOG" \
    NVM_FIXTURE_PREVIOUS="$nvm_previous" \
    PATH="$BREW_FIXTURE_BIN:$NVM_FIXTURE_BIN:/usr/bin:/bin" \
    zsh -fc '
      source "$1"
      git() { [[ "$3" != tag ]] || print -r -- v0.40.3; }
      install_nvm_node >/dev/null
      [[ "$(command -v npm)" == "$NVM_FIXTURE_BIN/npm" ]]
    ' setup-nvm "$ROOT/setup.sh"
  if [[ "$nvm_previous" == v1.0.0 ]]; then
    [[ "$(<"$NVM_FIXTURE_LOG")" == $'reinstall-packages v1.0.0\nuninstall v1.0.0' ]] || {
      printf "install_nvm_node did not migrate and remove the previous default:\n" >&2
      sed 's/^/  /' "$NVM_FIXTURE_LOG" >&2
      exit 1
    }
  else
    [[ ! -s "$NVM_FIXTURE_LOG" ]] || {
      printf "install_nvm_node touched nvm for previous default %s:\n" "$nvm_previous" >&2
      sed 's/^/  /' "$NVM_FIXTURE_LOG" >&2
      exit 1
    }
  fi
done

log "Checking setup Yazi flavor install modes"
YAZI_FIXTURE_HOME="$CHECK_WORK_DIR/yazi-home"
YAZI_FIXTURE_BIN="$YAZI_FIXTURE_HOME/bin"
YAZI_FIXTURE_LOG="$YAZI_FIXTURE_HOME/ya-calls.log"
mkdir -p "$YAZI_FIXTURE_BIN"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"$YA_FIXTURE_LOG"\n' >"$YAZI_FIXTURE_BIN/ya"
chmod +x "$YAZI_FIXTURE_BIN/ya"
# A declared flavor is installed at its pinned revision and moved to the
# latest release only with --update.
for yazi_case in pinned update; do
  : >"$YAZI_FIXTURE_LOG"
  env HOME="$YAZI_FIXTURE_HOME" YA_FIXTURE_LOG="$YAZI_FIXTURE_LOG" \
    PATH="$YAZI_FIXTURE_BIN:/usr/bin:/bin" YAZI_CASE="$yazi_case" zsh -fc '
      source "$1"
      if [[ "$YAZI_CASE" == update ]]; then
        parse_args --update
      fi
      install_yazi_flavor >/dev/null
    ' setup-yazi "$ROOT/setup.sh"
  case "$yazi_case" in
    pinned) yazi_expected="pkg install" ;;
    update) yazi_expected="pkg upgrade yazi-rs/flavors:catppuccin-mocha" ;;
  esac
  [[ "$(<"$YAZI_FIXTURE_LOG")" == "$yazi_expected" ]] || {
    printf "install_yazi_flavor ran the wrong ya command for %s:\n" "$yazi_case" >&2
    sed 's/^/  /' "$YAZI_FIXTURE_LOG" >&2
    exit 1
  }
done
rg -Fq 'use = "yazi-rs/flavors:catppuccin-mocha"' home/.config/yazi/package.toml

log "Checking native CLI installation without npm or Homebrew"
CLI_FIXTURE_HOME="$CHECK_WORK_DIR/native-cli-home"
CLI_FIXTURE_LOG="$CHECK_WORK_DIR/native-cli-calls.log"
mkdir -p "$CLI_FIXTURE_HOME"
# The failure cases run while no binary is installed yet. On a repeat run an
# installed Claude Code updates itself instead of downloading the installer;
# Codex has no updater and reruns its installer.
for cli in claude codex; do
  for install_case in download-failure installer-failure success repeat; do
    expected_exit=0
    case "$install_case" in
      download-failure) expected_exit=22 ;;
      installer-failure) expected_exit=17 ;;
    esac
    actual_exit=0
    : >"$CLI_FIXTURE_LOG"
    env HOME="$CLI_FIXTURE_HOME" PATH=/usr/bin:/bin \
      CLI_INSTALL_CASE="$install_case" CLI_FIXTURE_LOG="$CLI_FIXTURE_LOG" zsh -fc '
        source "$1"
        curl() {
          print -r -- "curl $2" >>"$CLI_FIXTURE_LOG"
          [[ "$1" == -fsSL ]]
          [[ "$CLI_INSTALL_CASE" != download-failure ]] || return 22
          if [[ "$CLI_INSTALL_CASE" == installer-failure ]]; then
            print -r -- "exit 17"
            return
          fi
          case "$2" in
            https://claude.ai/install.sh) print -r -- cli=claude ;;
            https://chatgpt.com/codex/install.sh) print -r -- cli=codex ;;
            *) return 1 ;;
          esac
          cat <<"SH"
set -eu
[ "${PATH%%:*}" = "$HOME/.local/bin" ]
if [ "$cli" = codex ]; then
  [ "$CODEX_NON_INTERACTIVE" = 1 ]
  [ "$CODEX_INSTALL_DIR" = "$HOME/.local/bin" ]
  [ "$*" = "--release latest" ]
else
  [ "$*" = latest ]
fi
mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/$cli" <<BIN
#!/bin/sh
printf "%s %s\\n" "$cli" "\$1" >>"$CLI_FIXTURE_LOG"
[ "\$1" = --version ] || [ "\$1" = update ]
BIN
chmod +x "$HOME/.local/bin/$cli"
SH
        }
        "install_${2}_cli"
      ' setup-native-cli "$ROOT/setup.sh" "$cli" \
      >"$CHECK_WORK_DIR/native-cli.log" 2>&1 || actual_exit=$?
    if (( actual_exit != expected_exit )); then
      cat "$CHECK_WORK_DIR/native-cli.log" >&2
      printf 'Unexpected %s %s exit: %s (expected %s)\n' \
        "$cli" "$install_case" "$actual_exit" "$expected_exit" >&2
      exit 1
    fi
    case "$cli:$install_case" in
      claude:success)
        cli_expected=$'curl https://claude.ai/install.sh\nclaude --version' ;;
      claude:repeat)
        cli_expected=$'claude update\nclaude --version' ;;
      claude:*)
        cli_expected='curl https://claude.ai/install.sh' ;;
      codex:success | codex:repeat)
        cli_expected=$'curl https://chatgpt.com/codex/install.sh\ncodex --version' ;;
      codex:*)
        cli_expected='curl https://chatgpt.com/codex/install.sh' ;;
    esac
    [[ "$(<"$CLI_FIXTURE_LOG")" == "$cli_expected" ]] || {
      printf 'Unexpected %s %s commands:\n' "$cli" "$install_case" >&2
      sed 's/^/  /' "$CLI_FIXTURE_LOG" >&2
      exit 1
    }
  done
done

log "Checking kitty installer version skip"
KITTY_FIXTURE_HOME="$CHECK_WORK_DIR/kitty-home"
KITTY_FIXTURE_LOG="$KITTY_FIXTURE_HOME/calls.log"
mkdir -p "$KITTY_FIXTURE_HOME/kitty.app/Contents/MacOS"
printf '#!/bin/sh\nprintf "kitty %%s created by Kovid Goyal\\n" "$KITTY_FIXTURE_VERSION"\n' \
  >"$KITTY_FIXTURE_HOME/kitty.app/Contents/MacOS/kitty"
chmod +x "$KITTY_FIXTURE_HOME/kitty.app/Contents/MacOS/kitty"
# The installer runs only when the app is missing or behind
# current-version.txt; the ~/.local/bin links are refreshed either way.
for kitty_case in current outdated missing; do
  : >"$KITTY_FIXTURE_LOG"
  rm -f "$KITTY_FIXTURE_HOME/.local/bin/kitty" "$KITTY_FIXTURE_HOME/.local/bin/kitten"
  env HOME="$KITTY_FIXTURE_HOME" PATH=/usr/bin:/bin KITTY_CASE="$kitty_case" \
    KITTY_FIXTURE_LOG="$KITTY_FIXTURE_LOG" KITTY_FIXTURE_VERSION=0.48.2 zsh -fc '
      source "$1"
      log() { :; }
      KITTY_APP_DIR="$HOME/kitty.app"
      [[ "$KITTY_CASE" != missing ]] || KITTY_APP_DIR="$HOME/missing.app"
      [[ "$KITTY_CASE" != current ]] || KITTY_FIXTURE_VERSION=0.49.2
      curl() {
        [[ "$1" == -fsSL ]]
        print -r -- "curl ${2##*/}" >>"$KITTY_FIXTURE_LOG"
        case "$2" in
          https://sw.kovidgoyal.net/kitty/current-version.txt) print -r -- 0.49.2 ;;
          https://sw.kovidgoyal.net/kitty/installer.sh)
            print -r -- "echo \"installer \$*\" >>\"$KITTY_FIXTURE_LOG\"" ;;
          *) return 1 ;;
        esac
      }
      install_kitty
      [[ -L "$HOME/.local/bin/kitty" && -L "$HOME/.local/bin/kitten" ]]
    ' setup-kitty "$ROOT/setup.sh"
  case "$kitty_case" in
    current) kitty_expected='curl current-version.txt' ;;
    outdated)
      kitty_expected=$'curl current-version.txt\ncurl installer.sh\ninstaller launch=n' ;;
    missing) kitty_expected=$'curl installer.sh\ninstaller launch=n' ;;
  esac
  [[ "$(<"$KITTY_FIXTURE_LOG")" == "$kitty_expected" ]] || {
    printf 'install_kitty ran the wrong commands for %s:\n' "$kitty_case" >&2
    sed 's/^/  /' "$KITTY_FIXTURE_LOG" >&2
    exit 1
  }
done

log "Checking SbarLua install stamp and cleanup"
SBARLUA_FIXTURE_HOME="$CHECK_WORK_DIR/sbarlua-home"
SBARLUA_FIXTURE_TMP="$CHECK_WORK_DIR/sbarlua-clone"
SBARLUA_FIXTURE_DIR="$SBARLUA_FIXTURE_HOME/.local/share/sketchybar_lua"
SBARLUA_FIXTURE_LOG="$CHECK_WORK_DIR/sbarlua-git.log"
sbarlua_commit="$(printf 'a%.0s' {1..40})"
sbarlua_cloned_commit="$(printf 'b%.0s' {1..40})"
# A matching stamp costs one ls-remote and no clone; a build installs and
# stamps the cloned commit, not the ls-remote tip; a failed build must still
# remove its clone.
for sbarlua_case in current install build-failure; do
  rm -rf "$SBARLUA_FIXTURE_HOME"
  : >"$SBARLUA_FIXTURE_LOG"
  if [[ "$sbarlua_case" == current ]]; then
    mkdir -p "$SBARLUA_FIXTURE_DIR"
    : >"$SBARLUA_FIXTURE_DIR/sketchybar.so"
    printf '%s\n' "$sbarlua_commit" >"$SBARLUA_FIXTURE_DIR/.dotfiles-ref"
  fi
  sbarlua_exit=0
  env HOME="$SBARLUA_FIXTURE_HOME" PATH=/usr/bin:/bin \
    SBARLUA_FIXTURE_TMP="$SBARLUA_FIXTURE_TMP" SBARLUA_CASE="$sbarlua_case" \
    SBARLUA_FIXTURE_LOG="$SBARLUA_FIXTURE_LOG" SBARLUA_COMMIT="$sbarlua_commit" \
    SBARLUA_CLONED_COMMIT="$sbarlua_cloned_commit" zsh -fc '
      source "$1"
      log() { :; }
      info() { :; }
      install_sketchybar_helpers() { :; }
      mktemp() {
        command mkdir -p "$SBARLUA_FIXTURE_TMP"
        print -r -- "$SBARLUA_FIXTURE_TMP"
      }
      git() {
        print -r -- "$1" >>"$SBARLUA_FIXTURE_LOG"
        case "$1" in
          ls-remote) printf "%s\tHEAD\n" "$SBARLUA_COMMIT" ;;
          clone) : >"${@[-1]}/Makefile" ;;
          -C) print -r -- "$SBARLUA_CLONED_COMMIT" ;;
          *) return 1 ;;
        esac
      }
      make() { [[ "$SBARLUA_CASE" != build-failure ]] && command mkdir -p "$HOME/.local/share/sketchybar_lua"; }
      install_sketchybar_assets
    ' setup-sbarlua "$ROOT/setup.sh" >"$CHECK_WORK_DIR/sbarlua.log" 2>&1 \
    || sbarlua_exit=$?
  case "$sbarlua_case" in
    current)
      (( sbarlua_exit == 0 )) && [[ ! -e "$SBARLUA_FIXTURE_TMP" ]] \
        && [[ "$(<"$SBARLUA_FIXTURE_LOG")" == ls-remote ]] ;;
    install)
      (( sbarlua_exit == 0 )) && [[ ! -e "$SBARLUA_FIXTURE_TMP" ]] \
        && [[ "$(<"$SBARLUA_FIXTURE_DIR/.dotfiles-ref")" == "$sbarlua_cloned_commit" ]] ;;
    build-failure)
      (( sbarlua_exit != 0 )) && [[ ! -e "$SBARLUA_FIXTURE_TMP" ]] ;;
  esac || {
    cat "$CHECK_WORK_DIR/sbarlua.log" >&2
    printf 'install_sketchybar_assets %s: exit %s, clone directory %s\n' \
      "$sbarlua_case" "$sbarlua_exit" \
      "$([[ -e "$SBARLUA_FIXTURE_TMP" ]] && echo leaked || echo removed)" >&2
    exit 1
  }
done

log "Checking Xcode license preflight"
zsh -fc '
  source "$1"

  XCODEBUILD_CALLS=0
  XCODEBUILD_EXIT=1
  xcode-select() { print -r -- "$DEVELOPER_DIR"; }
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

log "Checking macOS defaults"
SYSTEM_DEFAULTS_LOG="$CHECK_WORK_DIR/system-defaults.log"
env SYSTEM_DEFAULTS_LOG="$SYSTEM_DEFAULTS_LOG" zsh -fc '
  source "$1"
  log() { :; }
  info() { :; }
  osascript() { :; }
  defaults() { print -r -- "$*" >>"$SYSTEM_DEFAULTS_LOG"; }
  killall() { print -r -- "killall $*" >>"$SYSTEM_DEFAULTS_LOG"; }
  sudo_run() { print -r -- "$*" >>"$SYSTEM_DEFAULTS_LOG"; }

  setup_system_preferences
  for expected in \
    "write com.apple.AppleMultitouchTrackpad Clicking -bool true" \
    "write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true" \
    "-currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1" \
    "killall Dock" "killall Finder" "nvram StartupMute=%01"; do
    grep -Fxq -- "$expected" "$SYSTEM_DEFAULTS_LOG"
  done
' setup-system-defaults "$ROOT/setup.sh"

log "Checking setup service failure propagation"
SERVICE_FIXTURE_LOG="$SETUP_SNAPSHOT_DIR/services.log"
env SERVICE_FIXTURE_LOG="$SERVICE_FIXTURE_LOG" zsh -fc '
  source "$1"
  skip() { :; }
  sleep() { :; }

  expect_failure() {
    if "$@"; then
      printf "Expected setup service failure: %s\n" "$1" >&2
      exit 1
    fi
  }

  process_running() { return 1; }
  open() { return 1; }
  expect_failure restart_openusage

  open() { return 0; }
  wait_for_aerospace() { return 1; }
  expect_failure restart_aerospace

  # A running server whose version matches the CLI is reloaded in place; a
  # version mismatch quits and relaunches it.
  AEROSPACE_SERVER_VERSION=1.0.0
  AEROSPACE_QUITS=0
  process_running() { [[ "$1" == AeroSpace ]]; }
  aerospace() {
    [[ "$1" != --version ]] || printf \
      "aerospace CLI client version: 1.0.0\nAeroSpace.app server version: %s\n" \
      "$AEROSPACE_SERVER_VERSION"
  }
  osascript() { AEROSPACE_QUITS=$(( AEROSPACE_QUITS + 1 )); }
  wait_for_process_exit() { return 0; }
  wait_for_aerospace() { return 0; }
  preflight_aerospace_config() { return 0; }
  restart_aerospace
  (( AEROSPACE_QUITS == 0 ))
  AEROSPACE_SERVER_VERSION=0.9.0
  restart_aerospace
  (( AEROSPACE_QUITS == 1 ))

  brew() { return 0; }
  sketchybar() { return 1; }
  expect_failure restart_sketchybar

  OPENUSAGE_EXIT=0
  AEROSPACE_EXIT=0
  SKETCHYBAR_EXIT=0
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

  assert_service_case() {
    local expected_exit="$1"
    local expected_calls="$2"
    local actual_exit=0
    : >"$SERVICE_FIXTURE_LOG"
    restart_services >/dev/null 2>&1 || actual_exit=$?
    [[ "$actual_exit" == "$expected_exit" ]]
    [[ "$(<"$SERVICE_FIXTURE_LOG")" == "$expected_calls" ]]
  }

  all_calls="openusage
aerospace
sketchybar"
  assert_service_case 0 "$all_calls"
  OPENUSAGE_EXIT=1
  assert_service_case 1 "$all_calls"
  OPENUSAGE_EXIT=0
  AEROSPACE_EXIT=1
  assert_service_case 1 "openusage
aerospace"
  AEROSPACE_EXIT=0
  SKETCHYBAR_EXIT=1
  assert_service_case 1 "$all_calls"

  preflight_setup accept_xcode_license install_homebrew install_brew_packages \
    link_dotfiles install_claude_cli install_codex_cli install_nvm_node \
    install_zinit install_zsh_plugins install_kitty install_sketchybar_assets \
    install_tmux_plugins install_yazi_flavor install_neovim_plugins () { :; }
  restart_services() { return 1; }
  print_summary() { print -r -- "summary ${1:-}" >>"$SERVICE_FIXTURE_LOG"; }
  : >"$SERVICE_FIXTURE_LOG"
  if main --skip-system-defaults >/dev/null 2>&1; then
    printf "Setup main accepted a failed required-service postflight.\n" >&2
    exit 1
  fi
  grep -Fxq -- "summary 1" "$SERVICE_FIXTURE_LOG" || {
    printf "Setup main skipped the summary after a failed postflight.\n" >&2
    exit 1
  }
' setup-services "$ROOT/setup.sh"
if rg 'pgrep -' setup.sh | rg -vqF 'pgrep -a -x "$1"'; then
  printf "Setup must check processes with process_running, which includes pgrep's ancestors.\n" >&2
  exit 1
fi

log "Checking Lua syntax"
while IFS= read -r file; do
  [[ -f "$file" ]] && luac -p "$file"
done < <(repo_files '*.lua'; print -r -- home/.config/sketchybar/sketchybarrc)

log "Checking Lua runtime regression fixtures"
lua tests/sketchybar_runtime_spec.lua "$ROOT"
lua tests/treesitter_sync_spec.lua "$ROOT"
lua tests/neovim_sync_spec.lua "$ROOT"

log "Checking shell and tmux runtime regression fixtures"
# The specs use separate temp dirs, tmux sockets and lock files, so they run
# in parallel; their output is printed in a fixed order once all have finished.
RUNTIME_SPECS=(
  shell_syntax aerospace_resize nvm_runtime zsh_completion zinit_update
  brew_bundle tmux_runtime tmux_restore
)
typeset -A RUNTIME_SPEC_PIDS
for spec in "${RUNTIME_SPECS[@]}"; do
  python3 "tests/${spec}_spec.py" "$ROOT" >"$CHECK_WORK_DIR/$spec.log" 2>&1 &
  RUNTIME_SPEC_PIDS[$spec]="$!"
done
runtime_spec_failed=0
for spec in "${RUNTIME_SPECS[@]}"; do
  wait "${RUNTIME_SPEC_PIDS[$spec]}" || runtime_spec_failed=1
  cat "$CHECK_WORK_DIR/$spec.log"
done
if (( runtime_spec_failed )); then
  printf "Runtime regression fixtures failed.\n" >&2
  exit 1
fi

log "Checking tmux session-manager behavior"
env "${ISOLATED_ENV[@]}" python3 - \
  "$ROOT/home/.config/tmux/scripts/session_manager.py" <<'PY'
import importlib.util
import sys
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("dotfiles_session_manager", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

checks = (
    (module.sanitize_label("  research  ") == "research", "label trimming"),
    (module.sanitize_label("   ") == "session", "empty-label fallback"),
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
toml_files=("${(@f)$(repo_files '*.toml')}")
python3 - "${toml_files[@]}" <<'PY'
import sys
import tomllib
from pathlib import Path

for name in sys.argv[1:]:
    path = Path(name)
    if path.is_file():
        with path.open("rb") as handle:
            tomllib.load(handle)
PY

log "Checking JSON and JSONC"
while IFS= read -r file; do
  [[ -f "$file" ]] && json5 --validate "$file"
done < <(repo_files '*.json' '*.jsonc')
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
[[ "$brew_trust_targets" == $'brew\tfelixkratz/formulae/sketchybar\ncask\tnikitabobko/tap/aerospace\ncask\tabue-ammar/tinycast/tinycast\ncask\tphibrowser/tap/phi' ]]

log "Checking AI usage fixtures"
fixture_root="$CHECK_WORK_DIR/openusage"
mkdir -p "$fixture_root"/{object,array,empty,malformed}
for provider in codex claude; do
  jq -n '
    {
      lines: [
        {type: "progress", label: "Session", limit: 100, used: 25},
        {type: "progress", label: "Weekly", limit: 100, used: 80}
      ]
    }
  ' >"$fixture_root/object/${provider}.json"
  jq -n '[
    {
      lines: [
        {type: "progress", label: "Session", limit: 100, used: 40},
        {type: "progress", label: "Weekly", limit: 100, used: 10}
      ]
    }
  ]' >"$fixture_root/array/${provider}.json"
  : >"$fixture_root/empty/${provider}.json"
  printf '{invalid\n' >"$fixture_root/malformed/${provider}.json"
done

typeset -A usage_output
for kind in object array empty malformed; do
  usage_output[$kind]="$(env "${ISOLATED_ENV[@]}" \
    OPENUSAGE_FIXTURE_DIR="$fixture_root/$kind" \
    zsh home/.config/sketchybar/scripts/ai_usage.sh)"
done

for provider in codex claude; do
  assert_line "${usage_output[object]}" "${provider}_status=ok"
  assert_line "${usage_output[object]}" "${provider}_session=75"
  assert_line "${usage_output[object]}" "${provider}_weekly=20"
  assert_line "${usage_output[array]}" "${provider}_status=ok"
  assert_line "${usage_output[array]}" "${provider}_session=60"
  assert_line "${usage_output[array]}" "${provider}_weekly=90"
  assert_line "${usage_output[empty]}" "${provider}_status=empty"
  assert_line "${usage_output[malformed]}" "${provider}_status=parse_error"
  for kind in object array empty malformed; do
    bar_path="$(
      awk -F= -v key="${provider}_bar" \
        '$1 == key { print substr($0, index($0, "=") + 1); exit }' \
        <<<"${usage_output[$kind]}"
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
  done
done

log "Checking generated-state boundaries"
[[ -s home/.codex/AGENTS.md ]]
if git check-ignore --no-index -q home/.codex/AGENTS.md; then
  printf "Shared Codex instructions must not be Git-ignored.\n" >&2
  exit 1
fi
codex_local_paths=(config.toml AGENTS.override.md AGENTS.md.bak skills/test/SKILL.md future-state.json)
for local_path in "${codex_local_paths[@]}"; do
  git check-ignore --no-index -q "home/.codex/$local_path"
  env "${ISOLATED_ENV[@]}" zsh -c \
    'source "$1"; load_stow_ignore_patterns && stow_path_is_ignored "$2"' \
    zsh "$ROOT/setup.sh" ".codex/$local_path"
done
env "${ISOLATED_ENV[@]}" zsh -c '
  source "$1"
  load_stow_ignore_patterns && ! stow_path_is_ignored .codex/AGENTS.md
' zsh "$ROOT/setup.sh"

log "Checking tmux plugin manifest"
rg -Fxq 'source-file ~/.config/tmux/plugins.conf' home/.tmux.conf
if rg -q '^[[:space:]]*set -g @plugin' home/.tmux.conf; then
  printf "tmux plugins must be declared only in plugins.conf.\n" >&2
  exit 1
fi
# Validate the manifest with setup.sh's own parser. The isolated HOME has no
# plugin checkouts, so only the manifest rules apply.
env "${ISOLATED_ENV[@]}" zsh -fc '
  source "$1"
  preflight_tmux_plugins >/dev/null
' setup-tmux-plugins "$ROOT/setup.sh"

log "Checking tmux plugin install flow"
TPM_FIXTURE_HOME="$CHECK_WORK_DIR/tpm-home"
TPM_FIXTURE_LOG="$TPM_FIXTURE_HOME/calls.log"
tpm_repositories="$(
  env "${ISOLATED_ENV[@]}" zsh -fc \
    'source "$1"; tmux_plugin_repositories' \
    setup-tmux-plugins "$ROOT/setup.sh"
)"
mkdir -p "$TPM_FIXTURE_HOME/.tmux/plugins/tpm/scripts"
for tpm_script in install_plugins clean_plugins; do
  printf '#!/bin/sh\nprintf "%%s\\n" "%s" >>"$TPM_FIXTURE_LOG"\n' "$tpm_script" \
    >"$TPM_FIXTURE_HOME/.tmux/plugins/tpm/scripts/$tpm_script.sh"
done
# TPM is taken straight from the manifest, its install script runs before
# its clean script, and every other declared plugin is then updated.
tpm_expected=$'checkout tmux-plugins/tpm.git tpm\ninstall_plugins\nclean_plugins'
while IFS= read -r repository; do
  [[ "$repository" != tmux-plugins/tpm ]] || continue
  mkdir -p "$TPM_FIXTURE_HOME/.tmux/plugins/${repository##*/}/.git"
  tpm_expected+=$'\n'"checkout $repository.git ${repository##*/}"
done <<<"$tpm_repositories"
: >"$TPM_FIXTURE_LOG"
env HOME="$TPM_FIXTURE_HOME" TPM_FIXTURE_LOG="$TPM_FIXTURE_LOG" PATH=/usr/bin:/bin \
  zsh -fc '
    source "$1"
    log() { :; }
    ensure_latest_git_checkout() {
      print -r -- "checkout ${1#https://github.com/} ${2#$HOME/.tmux/plugins/}" \
        >>"$TPM_FIXTURE_LOG"
    }
    install_tmux_plugins
  ' setup-tmux-install "$ROOT/setup.sh"
[[ "$(<"$TPM_FIXTURE_LOG")" == "$tpm_expected" ]] || {
  printf "install_tmux_plugins ran the wrong steps:\n" >&2
  sed 's/^/  /' "$TPM_FIXTURE_LOG" >&2
  exit 1
}

log "Reading the Stow target-directory manifest"
manifest_target_dirs="$(
  env "${ISOLATED_ENV[@]}" zsh -c \
    'source "$1"; stow_target_directories' zsh "$ROOT/setup.sh"
)"
manifest_file_lines="$(
  sed -E -e 's/^[[:space:]]+//' -e 's/[[:space:]]+$//' -e '/^(#|$)/d' \
    "$FOLDING_MANIFEST"
)"
[[ -n "$manifest_target_dirs" && "$manifest_target_dirs" == "$manifest_file_lines" ]] || {
  printf "setup.sh does not consume the Stow folding manifest exactly.\n" >&2
  exit 1
}
# Codex writes machine-local state into ~/.codex, so Stow must link its files
# into a real directory instead of folding the directory into the repository.
assert_line "$manifest_target_dirs" ".codex"

log "Checking home package source boundaries"
boundary_failed=0
stow_target="$CHECK_WORK_DIR/stow-target"
create_stow_target "$stow_target"

worktree_leaf_plan="$CHECK_WORK_DIR/stow-worktree-leaf.plan"
candidate_leaf_plan="$CHECK_WORK_DIR/stow-candidate-leaf.plan"
write_stow_plan "$ROOT" "$stow_target" "$worktree_leaf_plan"
write_stow_plan "$CANDIDATE_ROOT" "$stow_target" "$candidate_leaf_plan"

ignored_plan="$CHECK_WORK_DIR/stow-ignored.plan"
mkdir -p "$CANDIDATE_ROOT/home/.config/yazi/flavors/test.yazi"
: >"$CANDIDATE_ROOT/home/.config/yazi/flavors/test.yazi/flavor.toml"
for local_path in "${codex_local_paths[@]}"; do
  mkdir -p "$CANDIDATE_ROOT/home/.codex/${local_path:h}"
  : >"$CANDIDATE_ROOT/home/.codex/$local_path"
done
write_stow_plan "$CANDIDATE_ROOT" "$stow_target" "$ignored_plan"
if ! cmp -s "$candidate_leaf_plan" "$ignored_plan"; then
  printf "Stow local-ignore rules expose generated fixture paths:\n" >&2
  diff -u "$candidate_leaf_plan" "$ignored_plan" >&2 || true
  boundary_failed=1
fi

if ! cmp -s "$worktree_leaf_plan" "$candidate_leaf_plan"; then
  printf "Worktree has Stow-visible paths absent from its Git snapshot:\n" >&2
  diff -u "$candidate_leaf_plan" "$worktree_leaf_plan" >&2 || true
  boundary_failed=1
fi

(( boundary_failed == 0 )) || exit 1

assert_line "$(<"$worktree_leaf_plan")" "LINK .codex/AGENTS.md"

log "Building and analyzing SketchyBar helpers"
helper_bin_dir="$CHECK_WORK_DIR/helpers"
# Build with the shared helpers/common.mk flags that setup.sh deploys, plus
# -Werror, so the flags under test are the flags in use.
make -C home/.config/sketchybar/helpers/event_providers \
  EXTRA_CFLAGS=-Werror BINDIR="$helper_bin_dir"
make -C home/.config/sketchybar/helpers/menus \
  EXTRA_CFLAGS=-Werror BINDIR="$helper_bin_dir"
for source in \
  home/.config/sketchybar/helpers/event_providers/cpu_load/cpu_load.c \
  home/.config/sketchybar/helpers/event_providers/network_load/network_load.c \
  home/.config/sketchybar/helpers/menus/menus.c; do
  clang --analyze -std=c99 -Wall -Wextra \
    -Xanalyzer -analyzer-output=text -Xanalyzer -analyzer-werror "$source"
done

log "Checking patch whitespace"
snapshot_git diff --cached --check HEAD -- :/

if (( RUN_LIVE_CHECKS )); then
  for command in aerospace brew fc-match fc-scan nvim tree-sitter; do
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
    file_name, index, postscript_names, families = (
        run(["fc-match", "-f", MATCH_FORMAT, pattern]).splitlines()[0].split("\t")
    )
    return file_name, index, postscript_names, families


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


def require_postscript_name(name: str) -> None:
    file_name, index, postscript_names, _ = font_match(f":postscriptname={name}")
    if name not in aliases(postscript_names):
        raise SystemExit(f"Missing PostScript face: {name}")
    if not scan_confirms(file_name, index, name, 1):
        raise SystemExit(f"fc-scan did not confirm PostScript face {name!r}")


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
    if not configured.startswith("postscript_name="):
        raise SystemExit(f"{key} must use postscript_name=: {configured}")
    require_postscript_name(configured.removeprefix("postscript_name="))

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
  treesitter_status="$(
    GIT_OPTIONAL_LOCKS=0 git -C "$treesitter_root" status --porcelain --untracked-files=no
  )"
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
    nvim -l - <<'LUA'
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
  # setup.sh's preflight already compares the active config with the
  # repository copy and runs the strict dry-run reload. It defers both when
  # AeroSpace is not running, which the live check treats as a failure.
  # The aerospace CLI needs the real user session, so no ISOLATED_ENV here.
  # -a: a kitty window opened by AeroSpace runs this check under AeroSpace.
  pgrep -a -x AeroSpace >/dev/null || {
    printf "AeroSpace is not running.\n" >&2
    exit 1
  }
  zsh -fc 'source "$1"; preflight_aerospace_config' \
    setup-aerospace "$ROOT/setup.sh"

  log "Checking tmux configuration in an isolated live server"
  installed_tmux_plugins="$HOME/.tmux/plugins"
  [[ -x "$installed_tmux_plugins/tpm/tpm" ]] || {
    printf "Installed TPM checkout is missing or not executable: %s\n" \
      "$installed_tmux_plugins/tpm/tpm" >&2
    exit 1
  }
  python3 tests/tmux_restore_spec.py "$ROOT" "$installed_tmux_plugins"
  create_stow_target "$ISOLATED_HOME"
  (
    cd "$ISOLATED_TMP"
    env HOME="$STOW_CONFIG_HOME" LC_ALL=C \
      stow --dir="$ROOT" --target="$ISOLATED_HOME" home
  )
  mkdir -p "$ISOLATED_HOME/.tmux"
  ln -s "$installed_tmux_plugins" "$ISOLATED_HOME/.tmux/plugins"
  tmux_config_output="$CHECK_WORK_DIR/tmux-config.out"
  TMUX_STARTED=1
  if ! env "${ISOLATED_ENV[@]}" tmux -S "$TMUX_SOCKET" \
    -f /dev/null \
    new-session -d -s dotfiles-check /usr/bin/tail -f /dev/null \
    >"$tmux_config_output" 2>&1; then
    sed 's/^/  /' "$tmux_config_output" >&2
    exit 1
  fi
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
  # Missing packages fail the check; merely outdated ones are setup.sh's job.
  export HOMEBREW_BUNDLE_NO_UPGRADE=1

  log "Checking live Brew bundle state"
  bundle_cask_skip="$(brew_bundle_cask_skip)"
  HOMEBREW_BUNDLE_CASK_SKIP="$bundle_cask_skip" \
    brew bundle check --file="$ROOT/Brewfile" --verbose

  log "Reporting unmanaged Brew dependencies"
  brew_bundle_report_extras "$ROOT/Brewfile" || BREW_AUDIT_INCOMPLETE=1
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
write_stow_plan "$ROOT" "$stow_target" "$final_worktree_leaf_plan"
if ! cmp -s "$candidate_leaf_plan" "$final_worktree_leaf_plan"; then
  printf "Stow-visible worktree paths changed while checks were running:\n" >&2
  diff -u "$candidate_leaf_plan" "$final_worktree_leaf_plan" >&2 || true
  exit 1
fi

cmp -s "$real_git_index" "$REAL_GIT_INDEX_SNAPSHOT" || {
  printf "The real Git index changed while checks were running.\n" >&2
  exit 1
}

if (( BREW_AUDIT_INCOMPLETE )); then
  printf "Required checks passed with warnings:\n  Optional Homebrew cleanup audit did not complete.\n"
else
  printf "All checks passed.\n"
fi
