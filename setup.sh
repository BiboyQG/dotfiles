#!/usr/bin/env zsh
set -euo pipefail

DOTFILES_DIR="${0:A:h}"
SKIPPED=()
CAN_SUDO=0
SUDO_KEEPALIVE_PID=""
APPLY_SYSTEM_DEFAULTS=1

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

ensure_latest_git_checkout() {
  local repository="$1"
  local destination="$2"

  if [[ ! -d "$destination/.git" ]]; then
    mkdir -p "${destination:h}"
    git clone --filter=blob:none --depth=1 "$repository" "$destination"
    return 0
  fi

  if [[ -n "$(git -C "$destination" status --porcelain)" ]]; then
    printf "Refusing to update modified Git checkout: %s\n" "$destination" >&2
    exit 1
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

append_line_once() {
  local file="$1"
  local line="$2"
  local header="${3:-}"

  mkdir -p "${file:h}"
  touch "$file"

  if ! grep -Fxq "$line" "$file"; then
    [[ -n "$header" ]] && printf "\n%s\n" "$header" >>"$file"
    printf "%s\n" "$line" >>"$file"
  fi
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

setup_system_preferences() {
  log "Applying macOS defaults"

  osascript -e 'tell application "System Settings" to quit' >/dev/null 2>&1 || true
  osascript -e 'tell application "System Preferences" to quit' >/dev/null 2>&1 || true

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

  if ! sudo_run nvram StartupMute=%01; then
    skip "Could not set the startup mute NVRAM value on this Mac."
  fi
  if ! sudo_run nvram SystemAudioVolume=' '; then
    skip "Could not set the system audio NVRAM value on this Mac."
  fi
}

install_homebrew() {
  log "Checking Homebrew"

  local brew_bin
  brew_bin="$(find_homebrew || true)"

  if [[ -z "$brew_bin" ]]; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    brew_bin="$(find_homebrew || true)"
  fi

  if [[ -z "$brew_bin" ]]; then
    printf "Homebrew installation completed but the brew executable was not found.\n" >&2
    exit 1
  fi

  eval "$("$brew_bin" shellenv)"
  append_line_once "$HOME/.zprofile" "eval \"\$($brew_bin shellenv)\"" "# Configure shell for Homebrew"
  append_line_once "$HOME/.zprofile" 'export PATH="$HOME/bin:$PATH"' "# Add ~/bin to PATH"
}

brew_trust_tap() {
  local tap="$1"

  if brew trust --help >/dev/null 2>&1; then
    brew trust --tap "$tap"
  fi
}

install_brew_packages() {
  log "Installing Homebrew packages"

  local -a taps=(
    felixkratz/formulae
    koekeishiya/formulae
    nikitabobko/tap
  )
  local tap
  for tap in "${taps[@]}"; do
    brew tap "$tap"
    brew_trust_tap "$tap"
  done

  local bundle_cask_skip="${HOMEBREW_BUNDLE_CASK_SKIP:-}"
  local pair cask app
  local -a unmanaged_cask_apps=(
    'arc:/Applications/Arc.app'
    'visual-studio-code:/Applications/Visual Studio Code.app'
  )
  for pair in "${unmanaged_cask_apps[@]}"; do
    cask="${pair%%:*}"
    app="${pair#*:}"
    if [[ -d "$app" ]] && ! brew list --cask "$cask" >/dev/null 2>&1; then
      bundle_cask_skip+="${bundle_cask_skip:+ }$cask"
      info "Keeping existing unmanaged app: ${app:t}"
    fi
  done

  HOMEBREW_BUNDLE_CASK_SKIP="$bundle_cask_skip" brew bundle install --file="$DOTFILES_DIR/Brewfile"
}

link_dotfiles() {
  log "Linking dotfiles with Stow"

  local container link_target
  for container in .config .config/zed .config/yazi .codex Library/LaunchAgents; do
    if [[ -L "$HOME/$container" ]]; then
      link_target="$(realpath "$HOME/$container")"
      if [[ "$link_target" != "$DOTFILES_DIR/$container" ]]; then
        printf "Refusing to stow into folded symlink: %s\n" "$HOME/$container" >&2
        printf "Replace it with a real directory before rerunning setup.\n" >&2
        exit 1
      fi
      rm "$HOME/$container"
    fi
    mkdir -p "$HOME/$container"
  done

  if ! stow --simulate --target="$HOME" .; then
    printf "Stow found conflicting files. Back them up or remove them, then rerun setup.\n" >&2
    exit 1
  fi

  stow --target="$HOME" .
}

link_vscode_config() {
  log "Linking VS Code user configuration"

  local vscode_user_dir="$HOME/Library/Application Support/Code/User"
  mkdir -p "$vscode_user_dir"

  local source target
  for source in "$DOTFILES_DIR/.vscode/vscode-settings.json" "$DOTFILES_DIR/.vscode/keybindings.json"; do
    if [[ "${source:t}" == "vscode-settings.json" ]]; then
      target="$vscode_user_dir/settings.json"
    else
      target="$vscode_user_dir/keybindings.json"
    fi

    if [[ -L "$target" && "$(realpath "$target")" == "$source" ]]; then
      continue
    fi
    if [[ -e "$target" && ! -L "$target" ]] && ! cmp -s "$source" "$target"; then
      printf "Refusing to replace different VS Code config: %s\n" "$target" >&2
      exit 1
    fi
    rm -f "$target"
    ln -s "$source" "$target"
  done
}

install_nvm_node() {
  log "Installing nvm and Node"

  export NVM_DIR="$HOME/.nvm"
  ensure_latest_git_checkout https://github.com/nvm-sh/nvm.git "$NVM_DIR"

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
  nvm use "$installed_node_version"

  set -u
}

install_codex_cli() {
  log "Installing latest Codex CLI"
  npm install --global @openai/codex@latest
}

install_zinit() {
  log "Installing latest zinit"

  local zinit_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
  ensure_latest_git_checkout https://github.com/zdharma-continuum/zinit.git "$zinit_dir"
}

install_zsh_plugins() {
  log "Installing latest zsh plugins"
  local zinit_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
  ZINIT_DIR="$zinit_dir" zsh -c 'source "$ZINIT_DIR/zinit.zsh"; zinit update --all'
}

install_neovim_plugins() {
  log "Installing latest Neovim plugins"
  NVIM_LOG_FILE=/dev/null nvim --headless "+Lazy! sync" +qa
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

install_sketchybar_assets() {
  log "Installing Sketchybar assets"

  if ! make -C "$DOTFILES_DIR/.config/sketchybar/helpers/event_providers"; then
    skip "Could not build SketchyBar event providers."
  fi
  if ! make -C "$DOTFILES_DIR/.config/sketchybar/helpers/menus"; then
    skip "Could not build the private-framework SketchyBar menu helper."
  fi

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

  local tpm_dir="$HOME/.tmux/plugins/tpm"
  ensure_latest_git_checkout https://github.com/tmux-plugins/tpm "$tpm_dir"

  /bin/bash "$tpm_dir/scripts/install_plugins.sh"

  local plugin plugin_dir repository
  while read -r plugin; do
    [[ -n "$plugin" ]] || continue
    plugin_dir="$HOME/.tmux/plugins/$plugin"
    if [[ ! -d "$plugin_dir/.git" ]]; then
      printf "TPM did not install expected plugin: %s\n" "$plugin" >&2
      exit 1
    fi
    repository="$(git -C "$plugin_dir" remote get-url origin)"
    ensure_latest_git_checkout "$repository" "$plugin_dir"
  done <"$DOTFILES_DIR/.config/tmux/plugins.txt"
}

accept_xcode_license() {
  log "Accepting Xcode license"

  if have xcodebuild && ! xcodebuild -license check >/dev/null 2>&1; then
    (( CAN_SUDO )) || ensure_sudo
    sudo_run xcodebuild -license accept
  fi
}

restart_services() {
  log "Restarting OpenUsage, AeroSpace, skhd, and sketchybar"

  if [[ -d /Applications/OpenUsage.app ]]; then
    if open -gja OpenUsage; then
      local openusage_ready=0
      for _ in {1..20}; do
        if curl -fsS --max-time 1 http://127.0.0.1:6736/v1/usage/codex >/dev/null 2>&1; then
          openusage_ready=1
          break
        fi
        sleep 0.25
      done
      (( openusage_ready )) || skip "OpenUsage started but its local API is not reachable."
    else
      skip "Could not open OpenUsage."
    fi
  fi

  if have sketchybar; then
    brew services restart sketchybar || brew services start sketchybar
  fi

  if have aerospace; then
    if pgrep -x AeroSpace >/dev/null; then
      osascript -e 'quit app "AeroSpace"' || skip "Could not stop AeroSpace."
      for _ in {1..20}; do
        pgrep -x AeroSpace >/dev/null || break
        sleep 0.1
      done
    fi

    if pgrep -x AeroSpace >/dev/null; then
      skip "AeroSpace did not stop; restart it manually."
    else
      open -g -a AeroSpace || skip "Could not open AeroSpace."
      sleep 1
      aerospace reload-config --no-gui || skip "Could not reload AeroSpace config."
    fi
  fi

  if have skhd; then
    skhd --restart-service || skhd --start-service
  fi
}

print_summary() {
  log "Setup complete"

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
  require_supported_platform
  require_command_line_tools
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
  link_vscode_config
  install_nvm_node
  install_codex_cli
  install_zinit
  install_zsh_plugins
  install_kitty
  install_sketchybar_assets
  install_tmux_plugins
  install_yazi_flavor
  install_neovim_plugins
  restart_services
  print_summary
}

if [[ "${ZSH_EVAL_CONTEXT:-}" == toplevel ]]; then
  main "$@"
fi
