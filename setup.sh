#!/usr/bin/env zsh
set -euo pipefail

DOTFILES_DIR="${0:A:h}"
NVM_VERSION="${NVM_VERSION:-v0.40.4}"
NODE_VERSION="${NODE_VERSION:-v24.16.0}"
ZINIT_REF="${ZINIT_REF:-773852f5888bb534452495edae41dc7516383b4a}"
SBARLUA_REF="${SBARLUA_REF:-dba9cc421b868c918d5c23c408544a28aadf2f2f}"
TPM_REF="${TPM_REF:-99469c4a9b1ccf77fade25842dc7bafbc8ce9946}"
SKIPPED=()
CAN_SUDO=0
SUDO_KEEPALIVE_PID=""

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

find_homebrew() {
  local candidate

  if have brew; then
    command -v brew
    return 0
  fi

  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" ]]; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_git_checkout() {
  local repository="$1"
  local ref="$2"
  local destination="$3"

  if [[ ! -d "$destination/.git" ]]; then
    mkdir -p "${destination:h}"
    git clone --filter=blob:none "$repository" "$destination"
  fi

  if [[ -n "$(git -C "$destination" status --porcelain)" ]]; then
    printf "Refusing to replace modified Git checkout: %s\n" "$destination" >&2
    exit 1
  fi

  if ! git -C "$destination" cat-file -e "${ref}^{commit}" 2>/dev/null; then
    git -C "$destination" fetch --depth=1 origin "$ref"
  fi

  git -C "$destination" checkout --quiet --detach "$ref"
  [[ "$(git -C "$destination" rev-parse HEAD)" == "$ref" ]]
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

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf "This setup script only supports macOS.\n" >&2
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

  sudo_run rm -f /private/var/vm/sleepimage
  sudo_run touch /private/var/vm/sleepimage
  sudo_run chflags uchg /private/var/vm/sleepimage
  sudo_run nvram StartupMute=%01
  sudo_run nvram SystemAudioVolume=' '
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
    manaflow-ai/cmux
    nikitabobko/tap
  )
  local tap
  for tap in "${taps[@]}"; do
    brew tap "$tap"
    brew_trust_tap "$tap"
  done

  brew bundle install --no-upgrade --file="$DOTFILES_DIR/Brewfile"
}

link_dotfiles() {
  log "Linking dotfiles with Stow"

  local container
  for container in .config .config/zed .codex Library/LaunchAgents; do
    if [[ -L "$HOME/$container" ]]; then
      printf "Refusing to stow into folded symlink: %s\n" "$HOME/$container" >&2
      printf "Replace it with a real directory before rerunning setup.\n" >&2
      exit 1
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

  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    PROFILE=/dev/null /bin/bash -c "set -euo pipefail; curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"
  else
    info "nvm already installed"
  fi

  set +u
  . "$NVM_DIR/nvm.sh"

  local installed_node_version
  nvm install "$NODE_VERSION"
  installed_node_version="$(nvm version "$NODE_VERSION")"

  if [[ "$installed_node_version" == "N/A" ]]; then
    printf "Failed to resolve installed Node version for %s\n" "$NODE_VERSION" >&2
    exit 1
  fi

  nvm alias default "$installed_node_version"
  nvm use "$installed_node_version"

  set -u
}

install_zinit() {
  log "Installing pinned zinit"

  local zinit_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
  ensure_git_checkout https://github.com/zdharma-continuum/zinit.git "$ZINIT_REF" "$zinit_dir"
}

install_kitty() {
  log "Installing kitty with the official installer"

  mkdir -p "$HOME/.local/bin"

  if [[ ! -d /Applications/kitty.app ]]; then
    curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n
  else
    info "kitty already installed"
  fi

  ln -sf /Applications/kitty.app/Contents/MacOS/kitty "$HOME/.local/bin/kitty"
  ln -sf /Applications/kitty.app/Contents/MacOS/kitten "$HOME/.local/bin/kitten"
}

install_cmux_cli() {
  log "Configuring cmux CLI"

  local cmux_bin="/Applications/cmux.app/Contents/Resources/bin/cmux"

  if [[ ! -x "$cmux_bin" ]]; then
    skip "cmux app binary not found at $cmux_bin"
    return 0
  fi

  mkdir -p "$HOME/.local/bin"
  ln -sf "$cmux_bin" "$HOME/.local/bin/cmux"

  if (( CAN_SUDO )); then
    sudo mkdir -p /usr/local/bin
    sudo ln -sf "$cmux_bin" /usr/local/bin/cmux
  else
    info "Linked cmux CLI in $HOME/.local/bin"
  fi
}

install_sketchybar_assets() {
  log "Installing Sketchybar assets"

  make -C "$DOTFILES_DIR/.config/sketchybar/helpers"

  local sbarlua_dir="$HOME/.local/share/sketchybar_lua"
  local sbarlua_stamp="$sbarlua_dir/.dotfiles-ref"
  if [[ -f "$sbarlua_dir/sketchybar.so" && -r "$sbarlua_stamp" \
    && "$(<"$sbarlua_stamp")" == "$SBARLUA_REF" ]]; then
    info "SbarLua already installed"
    return 0
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  ensure_git_checkout https://github.com/FelixKratz/SbarLua.git "$SBARLUA_REF" "$tmp_dir"
  make -C "$tmp_dir" install
  mkdir -p "$sbarlua_dir"
  printf "%s\n" "$SBARLUA_REF" >"$sbarlua_stamp"
  rm -rf "$tmp_dir"
}

install_tmux_plugins() {
  log "Installing tmux plugins"

  local tpm_dir="$HOME/.tmux/plugins/tpm"
  ensure_git_checkout https://github.com/tmux-plugins/tpm "$TPM_REF" "$tpm_dir"

  /bin/bash "$tpm_dir/scripts/install_plugins.sh"

  local plugin ref plugin_dir
  while read -r plugin ref; do
    [[ -n "$plugin" && -n "$ref" ]] || continue
    plugin_dir="$HOME/.tmux/plugins/$plugin"
    if [[ ! -d "$plugin_dir/.git" ]]; then
      printf "TPM did not install expected plugin: %s\n" "$plugin" >&2
      exit 1
    fi
    ensure_git_checkout "$(git -C "$plugin_dir" remote get-url origin)" "$ref" "$plugin_dir"
  done <"$DOTFILES_DIR/.config/tmux/plugins.lock"
}

accept_xcode_license() {
  log "Accepting Xcode license"

  if have xcodebuild; then
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
  require_macos
  ensure_sudo
  require_command_line_tools
  accept_xcode_license
  setup_system_preferences
  install_homebrew
  install_brew_packages
  link_dotfiles
  link_vscode_config
  install_nvm_node
  install_zinit
  install_kitty
  install_cmux_cli
  install_sketchybar_assets
  install_tmux_plugins
  restart_services
  print_summary
}

if [[ "${ZSH_EVAL_CONTEXT:-}" == toplevel ]]; then
  main "$@"
fi
