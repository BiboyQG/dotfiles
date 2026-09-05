#!/usr/bin/env zsh
set -euo pipefail

DOTFILES_DIR="${0:A:h}"
source "$DOTFILES_DIR/lib/brew_bundle.zsh"
source "$DOTFILES_DIR/lib/zinit_update.zsh"
SKIPPED=()
CAN_SUDO=0
SUDO_KEEPALIVE_PID=""
APPLY_SYSTEM_DEFAULTS=1
NEEDS_XCODE_LICENSE=0
STOW_IGNORE_PATTERNS=()
STOW_IGNORE_PATTERNS_LOADED=0
STOW_CONFIG_CWD="/var/empty"
STOW_CONFIG_HOME="$STOW_CONFIG_CWD/dotfiles-stow-home"

log() {
  printf "\n==> %s\n" "$*"
}

info() {
  printf "  %s\n" "$*"
}

warn() {
  printf "WARN: %s\n" "$*" >&2
}

skip() {
  SKIPPED+=("$*")
  warn "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

run_stow() {
  if [[ ! -d "$STOW_CONFIG_CWD" \
    || -e "$STOW_CONFIG_CWD/.stowrc" || -L "$STOW_CONFIG_CWD/.stowrc" \
    || -e "$STOW_CONFIG_HOME/.stowrc" || -L "$STOW_CONFIG_HOME/.stowrc" ]]; then
    printf "Stow isolation directory is unavailable or contains a resource file: %s\n" \
      "$STOW_CONFIG_CWD" >&2
    return 1
  fi

  (
    unset STOW_DIR
    export HOME="$STOW_CONFIG_HOME"
    export XDG_CONFIG_HOME="$STOW_CONFIG_HOME/.config"
    cd "$STOW_CONFIG_CWD"
    stow "$@"
  )
}

usage() {
  printf "usage: zsh setup.sh [--skip-system-defaults]\n"
}

parse_args() {
  while (( $# )); do
    case "$1" in
      --skip-system-defaults)
        APPLY_SYSTEM_DEFAULTS=0
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
}

find_homebrew() {
  if have brew; then
    command -v brew
    return 0
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    printf "/opt/homebrew/bin/brew\n"
    return 0
  fi

  return 1
}

checkout_latest_release() {
  local destination="$1"
  local release

  git -C "$destination" fetch --quiet --depth=1 origin 'refs/tags/*:refs/tags/*'
  release="$(git -C "$destination" tag --list 'v[0-9]*' --sort=-version:refname | head -n 1)"
  if [[ -z "$release" ]]; then
    printf "Could not resolve a release tag in %s\n" "$destination" >&2
    exit 1
  fi
  git -C "$destination" checkout --quiet "refs/tags/$release"
}

# Usage: ensure_latest_git_checkout <repository> <destination> [--release]
# --release pins the checkout to the newest v* tag instead of the branch tip.
ensure_latest_git_checkout() {
  local repository="$1"
  local destination="$2"
  local mode="${3:-}"

  if [[ ! -d "$destination/.git" ]]; then
    mkdir -p "${destination:h}"
    git clone --filter=blob:none --depth=1 "$repository" "$destination"
    [[ "$mode" == --release ]] && checkout_latest_release "$destination"
    return 0
  fi

  if [[ -n "$(git -C "$destination" status --porcelain)" ]]; then
    printf "Refusing to update modified Git checkout: %s\n" "$destination" >&2
    exit 1
  fi

  if [[ "$mode" == --release ]]; then
    checkout_latest_release "$destination"
    return 0
  fi

  git -C "$destination" fetch --prune origin

  local default_ref branch
  default_ref="$(git -C "$destination" symbolic-ref --quiet --short refs/remotes/origin/HEAD || true)"
  if [[ -z "$default_ref" ]]; then
    for default_ref in origin/main origin/master; do
      git -C "$destination" show-ref --verify --quiet "refs/remotes/$default_ref" && break
      default_ref=""
    done
  fi

  if [[ -z "$default_ref" ]]; then
    printf "Could not resolve the default branch for %s\n" "$repository" >&2
    exit 1
  fi

  branch="${default_ref#origin/}"
  if git -C "$destination" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$destination" checkout --quiet "$branch"
  else
    git -C "$destination" checkout --quiet --track -b "$branch" "$default_ref"
  fi
  git -C "$destination" merge --ff-only "$default_ref"
}

ensure_sudo() {
  if sudo -n true >/dev/null 2>&1; then
    CAN_SUDO=1
  elif [[ -t 0 ]]; then
    log "Requesting administrator password once"
    sudo -v
    CAN_SUDO=1
  else
    skip "No cached sudo credential and no TTY; privileged setup steps will be skipped."
  fi

  if (( CAN_SUDO )); then
    while true; do
      sudo -n true >/dev/null 2>&1 || exit
      sleep 60
    done &
    SUDO_KEEPALIVE_PID=$!
  fi
}

cleanup_sudo() {
  [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
}

trap cleanup_sudo EXIT

sudo_run() {
  if (( CAN_SUDO )); then
    sudo "$@"
  else
    skip "Skipped sudo command: sudo $*"
  fi
}

require_command_line_tools() {
  log "Checking Xcode Command Line Tools"

  if ! xcode-select -p >/dev/null 2>&1; then
    printf "Xcode Command Line Tools are missing. Run: xcode-select --install\n" >&2
    exit 1
  fi
}

require_supported_platform() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf "This setup script only supports macOS.\n" >&2
    exit 1
  fi

  if [[ "$(uname -m)" != "arm64" ]]; then
    printf "This setup script only supports Apple Silicon Macs.\n" >&2
    exit 1
  fi
}

preflight_xcode_license() {
  NEEDS_XCODE_LICENSE=0
  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$developer_dir" != "/Library/Developer/CommandLineTools" ]] \
    && have xcodebuild && ! xcodebuild -license check >/dev/null 2>&1; then
    NEEDS_XCODE_LICENSE=1
  fi
}

preflight_git_checkout() {
  local checkout="$1"
  local status_output

  [[ -e "$checkout" || -L "$checkout" ]] || return 0
  if [[ ! -d "$checkout/.git" ]]; then
    printf "Expected an existing Git checkout: %s\n" "$checkout" >&2
    return 1
  fi
  if ! status_output="$(
    GIT_OPTIONAL_LOCKS=0 git -C "$checkout" status --porcelain 2>&1
  )"; then
    printf "Could not inspect Git checkout %s: %s\n" \
      "$checkout" "$status_output" >&2
    return 1
  fi
  if [[ -n "$status_output" ]]; then
    printf "Refusing to update modified Git checkout: %s\n" "$checkout" >&2
    return 1
  fi
}

preflight_github_checkout() {
  local repository="$1"
  local checkout="$2"
  local remote actual_repository

  [[ -e "$checkout" || -L "$checkout" ]] || return 0
  preflight_git_checkout "$checkout" || return 1
  remote="$(git -C "$checkout" remote get-url origin 2>/dev/null || true)"
  actual_repository="$(github_repository_from_remote "$remote" 2>/dev/null || true)"
  if [[ "${(L)actual_repository}" != "${(L)repository}" ]]; then
    printf "Unexpected origin for Git checkout %s at %s: %s\n" \
      "$repository" "$checkout" "${remote:-missing}" >&2
    return 1
  fi
}

preflight_existing_git_checkouts() {
  log "Checking existing dependency checkouts"
  preflight_github_checkout "nvm-sh/nvm" "$HOME/.nvm" || return 1
  preflight_github_checkout "zdharma-continuum/zinit" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git" || return 1
}

declared_brew_taps() {
  local brew_bin="$1"
  HOMEBREW_NO_AUTO_UPDATE=1 \
    "$brew_bin" bundle list --tap --file="$DOTFILES_DIR/Brewfile"
}

preflight_brew_taps() {
  local brew_bin
  brew_bin="$(find_homebrew || true)"
  [[ -n "$brew_bin" ]] || return 0

  log "Checking existing Homebrew taps"
  local output tap tap_dir remote actual_repository expected_repository
  local -a taps
  output="$(declared_brew_taps "$brew_bin")" || return 1
  taps=("${(@f)output}")
  for tap in "${taps[@]}"; do
    [[ -n "$tap" ]] || continue
    tap_dir="$("$brew_bin" --repository "$tap" 2>/dev/null || true)"
    [[ -e "$tap_dir" || -L "$tap_dir" ]] || continue
    preflight_git_checkout "$tap_dir" || return 1
    remote="$(git -C "$tap_dir" remote get-url origin 2>/dev/null || true)"
    actual_repository="$(github_repository_from_remote "$remote" 2>/dev/null || true)"
    expected_repository="${tap%%/*}/homebrew-${tap#*/}"
    if [[ "${(L)actual_repository}" != "${(L)expected_repository}" ]]; then
      printf "Unexpected origin for Homebrew tap %s: %s\n" \
        "$tap" "${remote:-missing}" >&2
      return 1
    fi
  done
}

preflight_zprofile() {
  if [[ -f "$HOME/.zprofile" && ! -L "$HOME/.zprofile" ]]; then
    if ! cmp -s "$DOTFILES_DIR/home/.zprofile" "$HOME/.zprofile" \
      && [[ -e "$HOME/.zprofile.local" || -L "$HOME/.zprofile.local" ]]; then
      printf "Refusing to replace both .zprofile and .zprofile.local. Merge them first.\n" >&2
      return 1
    fi
  fi
}

stow_target_directories() {
  local manifest="$DOTFILES_DIR/stow-target-dirs.txt"
  local line component
  local -a components
  local -A seen
  local safe_component='^[A-Za-z0-9._ -]+$'

  if [[ ! -r "$manifest" ]]; then
    printf "Missing Stow target directory manifest: %s\n" "$manifest" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" && "$line" != \#* ]] || continue

    components=("${(@s:/:)line}")
    if [[ "$line" == /* || "$line" == */ || "$line" == *//* ]]; then
      printf "Invalid Stow target directory: %s\n" "$line" >&2
      return 1
    fi
    for component in "${components[@]}"; do
      if [[ -z "$component" || "$component" == "." || "$component" == ".." \
        || ! "$component" =~ $safe_component ]]; then
        printf "Invalid Stow target directory: %s\n" "$line" >&2
        return 1
      fi
    done
    if [[ -n "${seen[$line]:-}" ]]; then
      printf "Duplicate Stow target directory: %s\n" "$line" >&2
      return 1
    fi
    seen[$line]=1
    print -r -- "$line"
  done <"$manifest"
}

load_stow_ignore_patterns() {
  local manifest="$DOTFILES_DIR/home/.stow-local-ignore"
  local line regex regex_status

  (( STOW_IGNORE_PATTERNS_LOADED )) && return 0
  if [[ ! -r "$manifest" ]]; then
    printf "Missing Stow ignore manifest: %s\n" "$manifest" >&2
    return 1
  fi

  STOW_IGNORE_PATTERNS=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" && "$line" != \#* ]] || continue
    if [[ "$line" == */* ]]; then
      regex="(^|/)(${line})(/|$)"
    else
      regex="^(${line})$"
    fi
    if [[ "" =~ $regex ]]; then
      regex_status=0
    else
      regex_status=$?
    fi
    if (( regex_status > 1 )); then
      printf "Invalid pattern in Stow ignore manifest: %s\n" "$line" >&2
      return 1
    fi
    STOW_IGNORE_PATTERNS+=("$line")
  done <"$manifest"
  STOW_IGNORE_PATTERNS_LOADED=1
}

stow_path_is_ignored() {
  local relative="$1"
  local subject pattern regex

  [[ "$relative" == ".stow-local-ignore" ]] && return 0
  load_stow_ignore_patterns || return 2
  for pattern in "${STOW_IGNORE_PATTERNS[@]}"; do
    if [[ "$pattern" == */* ]]; then
      subject="/$relative"
      regex="(^|/)(${pattern})(/|$)"
    else
      subject="${relative:t}"
      regex="^(${pattern})$"
    fi
    [[ "$subject" =~ $regex ]] && return 0
  done
  return 1
}

preflight_folded_container_payload() {
  local source="$1"
  local entry relative ignore_status

  for entry in "$source"/**/*(DN); do
    relative="${entry#$DOTFILES_DIR/home/}"
    if stow_path_is_ignored "$relative"; then
      printf "Ignored machine-local data would be stranded by Stow migration: %s\n" \
        "$entry" >&2
      return 1
    else
      ignore_status=$?
      (( ignore_status == 1 )) || return 1
    fi
  done
}

preflight_stow_manifests() {
  local output container source target resolved
  local -a containers

  output="$(stow_target_directories)" || return 1
  if [[ -z "$output" ]]; then
    printf "Stow target directory manifest is empty.\n" >&2
    return 1
  fi
  load_stow_ignore_patterns || return 1
  containers=("${(@f)output}")
  for container in "${containers[@]}"; do
    source="$DOTFILES_DIR/home/$container"
    target="$HOME/$container"
    if [[ ! -d "$source" || -L "$source" ]]; then
      printf "Stow target directory is not a source directory: %s\n" "$container" >&2
      return 1
    fi
    if [[ -L "$target" ]]; then
      resolved="$(realpath "$target" 2>/dev/null || true)"
      if [[ "$resolved" != "$source" ]]; then
        printf "Stow target directory is an unmanaged link: %s\n" "$target" >&2
        return 1
      fi
      preflight_folded_container_payload "$source" || return 1
    elif [[ -e "$target" && ! -d "$target" ]]; then
      printf "Stow target directory is not a directory: %s\n" "$target" >&2
      return 1
    fi
  done
}

preflight_stow_directory() {
  local source_dir="$1"
  local target_dir="$2"
  local source target resolved relative ignore_status

  for source in "$source_dir"/*(DN); do
    relative="${source#$DOTFILES_DIR/home/}"
    if stow_path_is_ignored "$relative"; then
      continue
    else
      ignore_status=$?
      (( ignore_status == 1 )) || return 1
    fi
    target="$target_dir/${source:t}"

    if [[ "$source" == "$DOTFILES_DIR/home/.zprofile" \
      && -f "$target" && ! -L "$target" ]]; then
      continue
    fi

    if [[ -d "$source" ]]; then
      if [[ -L "$target" ]]; then
        resolved="$(realpath "$target" 2>/dev/null || true)"
        if [[ "$resolved" != "$source" ]]; then
          printf "Stow conflict: %s is not managed by this repository.\n" "$target" >&2
          return 1
        fi
      elif [[ -e "$target" && ! -d "$target" ]]; then
        printf "Stow conflict: %s is not a directory.\n" "$target" >&2
        return 1
      elif [[ -d "$target" ]]; then
        preflight_stow_directory "$source" "$target" || return 1
      fi
    elif [[ -L "$target" ]]; then
      resolved="$(realpath "$target" 2>/dev/null || true)"
      if [[ "$resolved" != "$source" ]]; then
        printf "Stow conflict: %s is not managed by this repository.\n" "$target" >&2
        return 1
      fi
    elif [[ -e "$target" ]]; then
      printf "Stow conflict: %s already exists.\n" "$target" >&2
      return 1
    fi
  done
}

preflight_stow_simulation() {
  have stow || return 0

  local output container resolved pattern
  local -a containers
  local -a stow_args=(
    --dir="$DOTFILES_DIR"
    --simulate
    --restow
    --target="$HOME"
    --ignore='^\.zprofile$'
  )
  output="$(stow_target_directories)" || return 1
  containers=("${(@f)output}")
  for container in "${containers[@]}"; do
    if [[ -L "$HOME/$container" ]]; then
      resolved="$(realpath "$HOME/$container" 2>/dev/null || true)"
      if [[ "$resolved" == "$DOTFILES_DIR/home/$container" ]]; then
        pattern="^${container//./\\.}(/|$)"
        stow_args+=(--ignore="$pattern")
      fi
    fi
  done

  run_stow "${stow_args[@]}" home
}

preflight_dotfiles() {
  log "Checking dotfile conflicts"
  preflight_stow_manifests || return 1
  preflight_zprofile || return 1
  preflight_stow_directory "$DOTFILES_DIR/home" "$HOME" || return 1
  preflight_stow_simulation || return 1
}

preflight_aerospace_config() {
  have aerospace || return 0
  if ! pgrep -x AeroSpace >/dev/null 2>&1; then
    info "Deferring AeroSpace validation until its server is running"
    return 0
  fi
  if ! aerospace list-workspaces --all --count >/dev/null 2>&1; then
    printf "AeroSpace is running, but its CLI is not responding.\n" >&2
    return 1
  fi

  local active_config
  if ! active_config="$(aerospace config --config-path)" \
    || [[ ! -r "$active_config" ]]; then
    printf "Could not read the active AeroSpace configuration.\n" >&2
    return 1
  fi
  if ! cmp -s "$DOTFILES_DIR/home/.config/aerospace/aerospace.toml" \
    "$active_config"; then
    printf "Active AeroSpace config differs from this repository: %s\n" \
      "$active_config" >&2
    return 1
  fi
  log "Checking AeroSpace configuration"
  aerospace reload-config --dry-run --warnings-as-errors --no-gui
}

tmux_plugin_repositories() {
  local manifest="$DOTFILES_DIR/home/.config/tmux/plugins.conf"
  local line repository owner name

  if [[ ! -r "$manifest" ]]; then
    printf "Missing tmux plugin manifest: %s\n" "$manifest" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" && "$line" != \#* ]] || continue
    repository="${line#*\'}"
    repository="${repository%\'}"
    owner="${repository%%/*}"
    name="${repository#*/}"
    if [[ "$line" != "set -g @plugin '$repository'" \
      || "$repository" != */* || -z "$owner" || -z "$name" || "$name" == */* \
      || "$repository" == *[!A-Za-z0-9._/-]* ]]; then
      printf "Invalid tmux plugin manifest line: %s\n" "$line" >&2
      return 1
    fi
    print -r -- "$repository"
  done <"$manifest"
}

github_repository_from_remote() {
  local remote="${1%.git}"
  case "$remote" in
    https://github.com/*)
      print -r -- "${remote#https://github.com/}"
      ;;
    https://git::@github.com/*)
      print -r -- "${remote#https://git::@github.com/}"
      ;;
    git@github.com:*)
      print -r -- "${remote#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      print -r -- "${remote#ssh://git@github.com/}"
      ;;
    *)
      return 1
      ;;
  esac
}

validate_tmux_plugin_checkout() {
  local repository="$1"
  local plugin_dir="$2"
  local remote actual_repository

  remote="$(git -C "$plugin_dir" remote get-url origin 2>/dev/null || true)"
  actual_repository="$(github_repository_from_remote "$remote" 2>/dev/null || true)"
  if [[ "$actual_repository" != "$repository" ]]; then
    printf "Unexpected origin for tmux plugin %s: %s\n" "$repository" "${remote:-missing}" >&2
    return 1
  fi
}

preflight_tmux_plugins() {
  log "Checking tmux plugin manifest"

  local output repository plugin plugin_dir
  local tpm_count=0
  local -a repositories
  local -A seen_plugins
  output="$(tmux_plugin_repositories)" || return 1
  repositories=("${(@f)output}")

  for repository in "${repositories[@]}"; do
    plugin="${repository##*/}"
    if [[ -n "${seen_plugins[$plugin]:-}" ]]; then
      printf "Duplicate tmux plugin directory in manifest: %s\n" "$plugin" >&2
      return 1
    fi
    seen_plugins[$plugin]=1
    [[ "$plugin" == "tpm" ]] && (( tpm_count += 1 ))

    plugin_dir="$HOME/.tmux/plugins/$plugin"
    if [[ ( -e "$plugin_dir" || -L "$plugin_dir" ) && ! -d "$plugin_dir/.git" ]]; then
      printf "Refusing to replace non-Git tmux plugin directory: %s\n" "$plugin_dir" >&2
      return 1
    fi
    if [[ -d "$plugin_dir/.git" ]]; then
      validate_tmux_plugin_checkout "$repository" "$plugin_dir" || return 1
      preflight_git_checkout "$plugin_dir" || return 1
    fi
  done

  if (( tpm_count != 1 )); then
    printf "The tmux plugin manifest must declare exactly one TPM repository.\n" >&2
    return 1
  fi
}

preflight_setup() {
  require_supported_platform || return 1
  require_command_line_tools || return 1
  preflight_xcode_license
  preflight_brew_taps || return 1
  preflight_existing_git_checkouts || return 1
  preflight_dotfiles || return 1
  preflight_tmux_plugins || return 1
  preflight_aerospace_config || return 1
}

setup_system_preferences() {
  log "Applying macOS defaults"

  osascript -e 'tell application "System Settings" to quit' >/dev/null 2>&1 || true
  osascript -e 'tell application "System Preferences" to quit' >/dev/null 2>&1 || true

  defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
  defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
  defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
  defaults write com.apple.LaunchServices LSQuarantine -bool false
  defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
  defaults write NSGlobalDomain KeyRepeat -int 1
  defaults write NSGlobalDomain InitialKeyRepeat -int 20
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  defaults write NSGlobalDomain com.apple.springing.enabled -bool true
  defaults write NSGlobalDomain com.apple.springing.delay -float 0
  defaults write com.apple.finder ShowStatusBar -bool true
  defaults write com.apple.finder ShowPathbar -bool true
  defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
  defaults write com.apple.finder _FXSortFoldersFirst -bool true
  defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
  defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
  defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
  defaults write com.apple.frameworks.diskimages skip-verify -bool true
  defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
  defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true
  defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true
  defaults write com.apple.frameworks.diskimages auto-open-rw-root -bool true
  defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true
  defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
  defaults write com.apple.finder WarnOnEmptyTrash -bool false
  defaults write com.apple.dock autohide -bool true
  defaults write com.apple.dock "autohide-delay" -float "0"

  local consumer
  for consumer in Dock Finder SystemUIServer; do
    killall "$consumer" >/dev/null 2>&1 || true
  done
  info "Key repeat defaults take effect after the next login."

  if ! sudo_run nvram StartupMute=%01; then
    skip "Could not set the startup mute NVRAM value on this Mac."
  fi
}

install_homebrew() {
  log "Checking Homebrew"

  local brew_bin
  brew_bin="$(find_homebrew || true)"

  if [[ -z "$brew_bin" ]]; then
    local installer
    if ! installer="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || [[ -z "$installer" ]]; then
      printf "Could not download the Homebrew installer.\n" >&2
      exit 1
    fi
    NONINTERACTIVE=1 /bin/bash -c "$installer"
    brew_bin="$(find_homebrew || true)"
  fi

  if [[ -z "$brew_bin" ]]; then
    printf "Homebrew installation completed but the brew executable was not found.\n" >&2
    exit 1
  fi

  eval "$("$brew_bin" shellenv)"
}

declared_brew_trust_targets() {
  local line dependency_type dependency

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in
      brew\ \"* | cask\ \"*)
        dependency_type="${line%% *}"
        dependency="${line#*\"}"
        dependency="${dependency%%\"*}"
        [[ "$dependency" == */*/* ]] \
          && print -r -- "$dependency_type"$'\t'"$dependency"
        ;;
    esac
  done <"$DOTFILES_DIR/Brewfile"
}

brew_trust_dependency() {
  local dependency_type="$1"
  local dependency="$2"

  if brew trust --help >/dev/null 2>&1; then
    case "$dependency_type" in
      brew)
        brew trust --formula "$dependency"
        ;;
      cask)
        brew trust --cask "$dependency"
        ;;
      *)
        printf "Unsupported Brew trust target type: %s\n" "$dependency_type" >&2
        return 1
        ;;
    esac
  fi
}

install_brew_packages() {
  log "Installing Homebrew packages"

  local tap_output tap
  local -a taps
  tap_output="$(declared_brew_taps "$(command -v brew)")"
  taps=("${(@f)tap_output}")
  for tap in "${taps[@]}"; do
    [[ -n "$tap" ]] || continue
    brew tap "$tap"
  done

  local trust_output trust_target dependency_type dependency
  local -a trust_targets
  trust_output="$(declared_brew_trust_targets)"
  trust_targets=("${(@f)trust_output}")
  for trust_target in "${trust_targets[@]}"; do
    [[ -n "$trust_target" ]] || continue
    IFS=$'\t' read -r dependency_type dependency <<<"$trust_target"
    brew_trust_dependency "$dependency_type" "$dependency"
  done

  local bundle_cask_skip
  bundle_cask_skip="$(brew_bundle_cask_skip)"
  HOMEBREW_BUNDLE_CASK_SKIP="$bundle_cask_skip" brew bundle install --file="$DOTFILES_DIR/Brewfile"
}

link_dotfiles() {
  log "Linking dotfiles with Stow"

  if ! have stow; then
    printf "GNU Stow is required before dotfiles can be linked.\n" >&2
    return 1
  fi
  preflight_stow_manifests || return 1
  preflight_zprofile || return 1
  preflight_stow_directory "$DOTFILES_DIR/home" "$HOME" || return 1
  preflight_stow_simulation || return 1

  if [[ -f "$HOME/.zprofile" && ! -L "$HOME/.zprofile" ]]; then
    if cmp -s "$DOTFILES_DIR/home/.zprofile" "$HOME/.zprofile"; then
      rm -- "$HOME/.zprofile"
    else
      mv "$HOME/.zprofile" "$HOME/.zprofile.local"
      info "Preserved the existing .zprofile as .zprofile.local"
    fi
  fi

  local output container
  local -a containers
  output="$(stow_target_directories)" || return 1
  containers=("${(@f)output}")
  for container in "${containers[@]}"; do
    if [[ -L "$HOME/$container" ]]; then
      rm "$HOME/$container"
    fi
    mkdir -p "$HOME/$container"
  done

  if ! run_stow --dir="$DOTFILES_DIR" --simulate --restow --target="$HOME" home; then
    printf "Stow found conflicting files. Back them up or remove them, then rerun setup.\n" >&2
    exit 1
  fi

  run_stow --dir="$DOTFILES_DIR" --restow --target="$HOME" home
}

install_nvm_node() {
  log "Installing nvm and Node"

  export NVM_DIR="$HOME/.nvm"
  ensure_latest_git_checkout https://github.com/nvm-sh/nvm.git "$NVM_DIR" --release

  set +u
  . "$NVM_DIR/nvm.sh"

  local installed_node_version
  nvm install node
  installed_node_version="$(nvm version node)"

  if [[ "$installed_node_version" == "N/A" ]]; then
    printf "Failed to resolve the latest installed Node version.\n" >&2
    exit 1
  fi

  nvm alias default "$installed_node_version"
  nvm deactivate --silent >/dev/null 2>&1 || true
  nvm use "$installed_node_version"

  set -u
}

install_claude_cli() {
  log "Installing latest Claude Code with the native installer"
  curl -fsSL https://claude.ai/install.sh \
    | PATH="$HOME/.local/bin:$PATH" /bin/bash -s -- latest
  "$HOME/.local/bin/claude" --version
}

install_codex_cli() {
  log "Installing latest Codex CLI with the standalone installer"
  curl -fsSL https://chatgpt.com/codex/install.sh \
    | PATH="$HOME/.local/bin:$PATH" CODEX_NON_INTERACTIVE=1 \
      CODEX_INSTALL_DIR="$HOME/.local/bin" /bin/sh -s -- --release latest
  "$HOME/.local/bin/codex" --version
}

install_zinit() {
  log "Installing latest zinit"

  local zinit_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
  ensure_latest_git_checkout https://github.com/zdharma-continuum/zinit.git "$zinit_dir"
}

install_zsh_plugins() {
  log "Installing latest zsh plugins"
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
  local update_log="$state_dir/zinit-update.log"
  local exit_code=0
  mkdir -p "$state_dir"
  # Source the declared plugin set, and retain diagnostics even if zinit exits
  # the child shell before returning to us.
  zsh -c 'source "$HOME/.zshrc"; zinit update --all --no-pager' </dev/null \
    >"$update_log" 2>&1 || exit_code=$?
  cat "$update_log"
  if ! zinit_update_succeeded "$update_log" "$exit_code" \
    || ! verify_zinit_checkouts "${XDG_DATA_HOME:-$HOME/.local/share}/zinit/plugins" "$update_log"; then
    printf "Zinit update failed verification; see %s\n" "$update_log" >&2
    return 1
  fi
  zsh -c 'source "$HOME/.zshrc"; zinit cclear' </dev/null
}

install_neovim_plugins() {
  log "Installing latest Neovim plugins"
  NVIM_LOG_FILE=/dev/null nvim --headless "+Lazy! sync" +qa
  NVIM_LOG_FILE=/dev/null nvim --headless -u NONE --noplugin -l "$DOTFILES_DIR/lib/sync_treesitter.lua"
}

install_yazi_flavor() {
  log "Installing latest Yazi flavor"

  local flavor="yazi-rs/flavors:catppuccin-mocha"
  local package_file="$HOME/.config/yazi/package.toml"

  if [[ -f "$package_file" ]] && grep -Fq "use = \"$flavor\"" "$package_file"; then
    ya pkg upgrade "$flavor"
  else
    ya pkg add "$flavor"
  fi
}

install_kitty() {
  log "Installing latest kitty with the official installer"

  mkdir -p "$HOME/.local/bin"
  curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n

  ln -sf /Applications/kitty.app/Contents/MacOS/kitty "$HOME/.local/bin/kitty"
  ln -sf /Applications/kitty.app/Contents/MacOS/kitten "$HOME/.local/bin/kitten"
}

install_sketchybar_helpers() {
  local helper_bin_dir="$HOME/.local/libexec/sketchybar"
  local build_dir
  build_dir="$(mktemp -d)"

  if ! make -C "$DOTFILES_DIR/home/.config/sketchybar/helpers/event_providers" BINDIR="$build_dir"; then
    rm -r -- "$build_dir"
    printf "Could not build required SketchyBar event providers.\n" >&2
    return 1
  fi

  mkdir -p "$helper_bin_dir"
  /usr/bin/install -m 755 "$build_dir/cpu_load" "$helper_bin_dir/cpu_load"
  /usr/bin/install -m 755 "$build_dir/network_load" "$helper_bin_dir/network_load"

  if make -C "$DOTFILES_DIR/home/.config/sketchybar/helpers/menus" BINDIR="$build_dir"; then
    /usr/bin/install -m 755 "$build_dir/menus" "$helper_bin_dir/menus"
  else
    rm -f -- "$helper_bin_dir/menus"
    skip "Could not build the optional private-framework SketchyBar menu helper."
  fi
  rm -r -- "$build_dir"
}

install_sketchybar_assets() {
  log "Installing Sketchybar assets"

  install_sketchybar_helpers

  local sbarlua_dir="$HOME/.local/share/sketchybar_lua"
  local sbarlua_stamp="$sbarlua_dir/.dotfiles-ref"
  local tmp_dir latest_commit
  tmp_dir="$(mktemp -d)"
  ensure_latest_git_checkout https://github.com/FelixKratz/SbarLua.git "$tmp_dir"
  latest_commit="$(git -C "$tmp_dir" rev-parse HEAD)"

  if [[ -f "$sbarlua_dir/sketchybar.so" && -r "$sbarlua_stamp" \
    && "$(<"$sbarlua_stamp")" == "$latest_commit" ]]; then
    info "SbarLua already installed"
    rm -rf "$tmp_dir"
    return 0
  fi

  make -C "$tmp_dir" install
  mkdir -p "$sbarlua_dir"
  printf "%s\n" "$latest_commit" >"$sbarlua_stamp"
  rm -rf "$tmp_dir"
}

install_tmux_plugins() {
  log "Installing latest tmux plugins"

  local output repository plugin plugin_dir tpm_repository=""
  local -a repositories
  output="$(tmux_plugin_repositories)"
  repositories=("${(@f)output}")

  for repository in "${repositories[@]}"; do
    if [[ "${repository##*/}" == "tpm" ]]; then
      tpm_repository="$repository"
      break
    fi
  done

  if [[ -z "$tpm_repository" ]]; then
    printf "The tmux plugin manifest does not declare TPM.\n" >&2
    return 1
  fi

  local tpm_dir="$HOME/.tmux/plugins/tpm"
  if [[ -d "$tpm_dir/.git" ]]; then
    validate_tmux_plugin_checkout "$tpm_repository" "$tpm_dir"
  fi
  ensure_latest_git_checkout "https://github.com/$tpm_repository.git" "$tpm_dir"
  validate_tmux_plugin_checkout "$tpm_repository" "$tpm_dir"

  /bin/bash "$tpm_dir/scripts/install_plugins.sh"

  for repository in "${repositories[@]}"; do
    plugin="${repository##*/}"
    [[ "$plugin" == "tpm" ]] && continue
    plugin_dir="$HOME/.tmux/plugins/$plugin"
    if [[ ! -d "$plugin_dir/.git" ]]; then
      printf "TPM did not install expected plugin: %s\n" "$plugin" >&2
      exit 1
    fi
    validate_tmux_plugin_checkout "$repository" "$plugin_dir"
    ensure_latest_git_checkout "https://github.com/$repository.git" "$plugin_dir"
  done
}

accept_xcode_license() {
  log "Accepting Xcode license"

  if (( NEEDS_XCODE_LICENSE )); then
    (( CAN_SUDO )) || ensure_sudo
    sudo_run xcodebuild -license accept
  fi
}

wait_for_process_exit() {
  local process="$1"
  local attempts="${2:-40}"
  local attempt
  for (( attempt = 1; attempt <= attempts; attempt++ )); do
    pgrep -x "$process" >/dev/null 2>&1 || return 0
    sleep 0.25
  done
  return 1
}

restart_openusage() {
  if [[ ! -d /Applications/OpenUsage.app ]]; then
    skip "OpenUsage is not installed."
    return 1
  fi

  if pgrep -x OpenUsage >/dev/null 2>&1; then
    if ! osascript -e 'quit app "OpenUsage"' >/dev/null; then
      skip "Could not stop OpenUsage."
      return 1
    fi
    if ! wait_for_process_exit OpenUsage 40; then
      skip "OpenUsage did not stop; restart it manually."
      return 1
    fi
  fi

  if ! open -gja OpenUsage; then
    skip "Could not open OpenUsage."
    return 1
  fi

  local attempt
  for attempt in {1..20}; do
    if curl -fsS --connect-timeout 1 --max-time 1 \
      http://127.0.0.1:6736/v1/usage/codex >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  skip "OpenUsage local API is not reachable after launch."
  return 1
}

aerospace_ready() {
  pgrep -x AeroSpace >/dev/null 2>&1 \
    && aerospace list-workspaces --all --count >/dev/null 2>&1
}

wait_for_aerospace() {
  local attempt
  for attempt in {1..40}; do
    aerospace_ready && return 0
    sleep 0.25
  done
  return 1
}

restart_aerospace() {
  if ! have aerospace; then
    skip "AeroSpace CLI is not installed."
    return 1
  fi

  if pgrep -x AeroSpace >/dev/null 2>&1; then
    if ! preflight_aerospace_config; then
      skip "AeroSpace configuration did not pass strict validation."
      return 1
    fi
    if ! osascript -e 'quit app "AeroSpace"'; then
      skip "Could not stop AeroSpace."
      return 1
    fi
    if ! wait_for_process_exit AeroSpace 40; then
      skip "AeroSpace did not stop; restart it manually."
      return 1
    fi
  fi

  if ! open -g -a AeroSpace; then
    skip "Could not open AeroSpace."
    return 1
  fi

  if ! wait_for_aerospace; then
    skip "AeroSpace started but its CLI is not ready."
    return 1
  fi
  if ! preflight_aerospace_config; then
    skip "AeroSpace configuration did not pass strict validation after launch."
    return 1
  fi
  if ! aerospace reload-config --no-gui; then
    skip "Could not reload AeroSpace config."
    return 1
  fi
  if ! wait_for_aerospace; then
    skip "AeroSpace config reloaded but its CLI is not ready."
    return 1
  fi
  return 0
}

restart_sketchybar() {
  if ! have sketchybar; then
    skip "SketchyBar CLI is not installed."
    return 1
  fi

  if ! brew services restart sketchybar && ! brew services start sketchybar; then
    skip "Could not start SketchyBar."
    return 1
  fi

  local attempt
  for attempt in {1..40}; do
    sketchybar --query bar >/dev/null 2>&1 && return 0
    sleep 0.25
  done
  skip "SketchyBar service started but is not responding."
  return 1
}

restart_skhd() {
  if ! have skhd; then
    skip "skhd CLI is not installed."
    return 1
  fi

  if ! skhd --restart-service && ! skhd --start-service; then
    skip "Could not start skhd."
    return 1
  fi

  local attempt
  for attempt in {1..40}; do
    launchctl print "gui/$(id -u)/com.koekeishiya.skhd" 2>/dev/null \
      | grep -Eq '^[[:space:]]*state = running$' && return 0
    sleep 0.25
  done
  skip "skhd restart returned successfully but its launchd job is not running."
  return 1
}

restart_services() {
  log "Restarting OpenUsage, AeroSpace, SketchyBar, and skhd"

  local failed=0
  restart_openusage || failed=1
  if restart_aerospace; then
    restart_sketchybar || failed=1
  else
    failed=1
    skip "AeroSpace is not ready; SketchyBar was not restarted."
  fi
  restart_skhd || failed=1

  if (( failed )); then
    printf "One or more required services failed postflight checks.\n" >&2
    return 1
  fi
}

print_summary() {
  local exit_code="${1:-0}"

  if (( exit_code )); then
    warn "Setup finished with failed service postflight checks"
  else
    log "Setup complete"
  fi

  if (( ${#SKIPPED[@]} )); then
    printf "Skipped steps:\n"
    local item
    for item in "${SKIPPED[@]}"; do
      printf "  - %s\n" "$item"
    done
  fi
}

main() {
  parse_args "$@"
  preflight_setup
  if (( APPLY_SYSTEM_DEFAULTS )); then
    ensure_sudo
  fi
  accept_xcode_license
  if (( APPLY_SYSTEM_DEFAULTS )); then
    setup_system_preferences
  else
    info "Skipping macOS defaults"
  fi
  install_homebrew
  install_brew_packages
  link_dotfiles
  install_claude_cli
  install_codex_cli
  install_nvm_node
  install_zinit
  install_zsh_plugins
  install_kitty
  install_sketchybar_assets
  install_tmux_plugins
  install_yazi_flavor
  install_neovim_plugins
  local exit_code=0
  restart_services || exit_code=1
  print_summary "$exit_code"
  return "$exit_code"
}

if [[ "${ZSH_EVAL_CONTEXT:-}" == toplevel ]]; then
  main "$@"
fi
