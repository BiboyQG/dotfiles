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

for command in json5 lua luac rg stow tmux; do
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
for file in setup.sh check.sh lib/*.zsh home/.zprofile home/.zshrc \
  home/.config/aerospace/scripts/resize-edge; do
  zsh -n "$file"
done
for file in \
  home/bin/abs \
  home/bin/ip; do
  /bin/bash -n "$file"
done

log "Checking public IP helper behavior"
IP_FIXTURE_DIR="$CHECK_WORK_DIR/ip-fixtures"
mkdir -p "$IP_FIXTURE_DIR"
cat >"$IP_FIXTURE_DIR/curl" <<'BASH'
#!/bin/bash
set -euo pipefail
url="${@: -1}"
case "$IP_MOCK_SCENARIO:$url" in
  primary_success:https://api.ipify.org) printf '203.0.113.7\n' ;;
  fallback:https://api.ipify.org) printf '999.1.2.3\n' ;;
  fallback:https://ipv4.icanhazip.com) printf '198.51.100.17\n' ;;
  *) exit 22 ;;
esac
BASH
chmod +x "$IP_FIXTURE_DIR/curl"

[[ "$(env "${ISOLATED_ENV[@]}" PATH="$IP_FIXTURE_DIR:$PATH" IP_MOCK_SCENARIO=primary_success "$ROOT/home/bin/ip")" == "203.0.113.7" ]]
[[ "$(env "${ISOLATED_ENV[@]}" PATH="$IP_FIXTURE_DIR:$PATH" IP_MOCK_SCENARIO=fallback "$ROOT/home/bin/ip")" == "198.51.100.17" ]]
if env "${ISOLATED_ENV[@]}" PATH="$IP_FIXTURE_DIR:$PATH" IP_MOCK_SCENARIO=all_fail "$ROOT/home/bin/ip" >/dev/null 2>"$IP_FIXTURE_DIR/stderr"; then
  printf "home/bin/ip succeeded when all endpoints failed.\n" >&2
  exit 1
fi
[[ "$(<"$IP_FIXTURE_DIR/stderr")" == "unable to determine public IPv4" ]]

log "Checking setup command-line behavior"
# The runs below source setup.sh and replace its steps afterwards, so a guard
# that called main during source would run the real steps.
[[ "$(tail -n 3 setup.sh)" == 'if [[ "${ZSH_EVAL_CONTEXT:-}" == toplevel ]]; then
  main "$@"
fi' ]] || {
  printf "setup.sh must keep main behind its source-safe entry guard\n" >&2
  exit 1
}

SETUP_CLI_POISON="$CHECK_WORK_DIR/setup-cli-poison"
# Only main and argument parsing run for real. Every other setup.sh function,
# and the listed commands, records its name instead, so a setup.sh that
# ignores its options fails here instead of setting up this Mac, whatever its
# steps are named. cleanup_sudo stays real because it is the EXIT trap.
run_setup_cli() {
  local setup_script="$1"
  shift
  env "${ISOLATED_ENV[@]}" zsh -fc '
    source "$1"
    POISON_MARKER="$2"
    shift 2
    poison() { print -r -- "$1" >>"$POISON_MARKER"; return 97; }
    for name in brew curl defaults git killall make npm open osascript stow sudo ya \
      ${(k)functions:#(main|parse_args|usage|cleanup_sudo|poison)}; do
      functions[$name]="poison $name"
    done
    main "$@"
  ' setup-cli "$setup_script" "$SETUP_CLI_POISON" "$@"
}

help_status=0
setup_help="$(run_setup_cli setup.sh --help)" || help_status=$?
setup_status=0
run_setup_cli setup.sh --invalid-check-option >/dev/null 2>&1 || setup_status=$?
[[ ! -e "$SETUP_CLI_POISON" ]] || {
  printf "setup.sh ran setup steps for --help or an invalid option:\n" >&2
  sed 's/^/  /' "$SETUP_CLI_POISON" >&2
  exit 1
}
(( help_status == 0 ))
grep -Fq 'usage:' <<<"$setup_help"
grep -Fq -- '--update' <<<"$setup_help"
(( setup_status == 2 )) || {
  printf "setup.sh returned %d for an invalid option; expected 2.\n" "$setup_status" >&2
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
  "$SETUP_FIXTURE_SOURCE/home/.claude/skills" \
  "$SETUP_FIXTURE_SOURCE/home/.codex" \
  "$SETUP_FIXTURE_SOURCE/home/.config/kitty" \
  "$SETUP_FIXTURE_SOURCE/home/.config/yazi" \
  "$SETUP_FIXTURE_SOURCE/home/.config/zed" \
  "$SETUP_FIXTURE_SOURCE/home/.config/preflight-boundary" \
  "$SETUP_FIXTURE_SOURCE/home/Library/LaunchAgents" \
  "$SETUP_FIXTURE_HOME/.config/preflight-boundary" \
  "$SETUP_FIXTURE_TMP" \
  "$SETUP_SNAPSHOT_DIR"
cp "$FOLDING_MANIFEST" "$SETUP_FIXTURE_SOURCE/stow-target-dirs.txt"
printf '.config/preflight-boundary\n' \
  >>"$SETUP_FIXTURE_SOURCE/stow-target-dirs.txt"
cp home/.stow-local-ignore \
  "$SETUP_FIXTURE_SOURCE/home/.stow-local-ignore"
printf 'fixture-ignored\n' \
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
          preflight_github_checkout "zdharma-continuum/zinit" "$5"
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

# An ignored entry below a folded sub-directory stays reachable through its
# link, and a Finder .DS_Store is not machine-local data, so neither blocks
# migration.
mkdir -p "$SETUP_FIXTURE_SOURCE/home/.config/yazi/plugins"
: >"$SETUP_FIXTURE_SOURCE/home/.config/yazi/plugins/fixture-ignored"
: >"$SETUP_FIXTURE_SOURCE/home/.config/yazi/.DS_Store"
ln -s "$SETUP_FIXTURE_SOURCE/home/.config/yazi" \
  "$SETUP_FIXTURE_HOME/.config/yazi"
assert_setup_preflight folded-reachable accept
rm -- "$SETUP_FIXTURE_HOME/.config/yazi" \
  "$SETUP_FIXTURE_SOURCE/home/.config/yazi/plugins/fixture-ignored" \
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

corrupt_checkout="$SETUP_FIXTURE_HOME/zinit.git"
mkdir -p "$corrupt_checkout/.git/objects"
printf 'not-a-valid-head\n' >"$corrupt_checkout/.git/HEAD"
assert_setup_preflight corrupt-git reject \
  "Could not inspect Git checkout $corrupt_checkout:" \
  -- git-checkout "$corrupt_checkout"

wrong_origin_checkout="$SETUP_FIXTURE_HOME/wrong-zinit"
git init --quiet "$wrong_origin_checkout"
git -C "$wrong_origin_checkout" remote add origin \
  https://github.com/example/not-zinit.git
assert_setup_preflight wrong-origin reject \
  "Unexpected origin for Git checkout zdharma-continuum/zinit at $wrong_origin_checkout: https://github.com/example/not-zinit.git" \
  -- github-checkout "$wrong_origin_checkout"

printf '../escape\n' >>"$SETUP_FIXTURE_SOURCE/stow-target-dirs.txt"
assert_setup_preflight invalid reject 'Invalid Stow target directory: ../escape'

rg -Fq 'use = "yazi-rs/flavors:catppuccin-mocha"' home/.config/yazi/package.toml
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

log "Checking shell runtime regression fixtures"
# The specs use separate temp dirs and lock files, so they run in parallel;
# their output is printed in a fixed order once all have finished.
RUNTIME_SPECS=(
  shell_syntax aerospace_resize zsh_completion zinit_update brew_bundle
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
jq empty home/.config/lockime/rules.json

log "Checking Brewfile and LaunchAgent"
ruby -c Brewfile >/dev/null
plutil -lint home/Library/LaunchAgents/com.biboy.openusage.plist >/dev/null
brew_trust_targets="$(
  env "${ISOLATED_ENV[@]}" zsh -c \
    'source "$1"; declared_brew_trust_targets' zsh "$ROOT/setup.sh"
)"
[[ "$brew_trust_targets" == $'brew\tfelixkratz/formulae/sketchybar\ncask\tnikitabobko/tap/aerospace\ncask\tabue-ammar/tinycast/tinycast\ncask\tphibrowser/tap/phi\ncask\toomol-lab/tap/lockime' ]]

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
assert_line "$manifest_target_dirs" ".config/zed"

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
assert_line "$(<"$worktree_leaf_plan")" "LINK .config/zed/keymap.json"
assert_line "$(<"$worktree_leaf_plan")" "LINK .config/zed/settings.json"

log "Building and analyzing SketchyBar helpers"
helper_bin_dir="$CHECK_WORK_DIR/helpers"
# Build with the shared helpers/common.mk flags that setup.sh deploys, plus
# -Werror, so the flags under test are the flags in use.
make -C home/.config/sketchybar/helpers/menus \
  EXTRA_CFLAGS=-Werror BINDIR="$helper_bin_dir"
clang --analyze -std=c99 -Wall -Wextra \
  -Xanalyzer -analyzer-output=text -Xanalyzer -analyzer-werror \
  home/.config/sketchybar/helpers/menus/menus.c

log "Checking patch whitespace"
snapshot_git diff --cached --check HEAD -- :/

if (( RUN_LIVE_CHECKS )); then
  for command in aerospace brew fc-match fc-scan; do
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
  printf "  Live font, AeroSpace, tmux, and Homebrew checks skipped; rerun with --live.\n"
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
