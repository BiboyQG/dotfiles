#!/usr/bin/env zsh
set -euo pipefail

DOTFILES_DIR="${0:A:h}"
NVM_VERSION="${NVM_VERSION:-v0.40.4}"
NODE_VERSION="${NODE_VERSION:-lts/*}"
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

  if ! have brew; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  eval "$("$(command -v brew)" shellenv)"

  local brew_bin
  brew_bin="$(command -v brew)"
  append_line_once "$HOME/.zprofile" "eval \"\$($brew_bin shellenv)\"" "# Configure shell for Homebrew"
  append_line_once "$HOME/.zprofile" 'export PATH="$HOME/bin:$PATH"' "# Add ~/bin to PATH"
}

brew_install_formula() {
  local package="$1"

  if brew list --formula "$package" >/dev/null 2>&1; then
    info "$package already installed"
  else
    brew install "$package"
  fi
}

brew_install_cask() {
  local package="$1"

  if brew list --cask "$package" >/dev/null 2>&1; then
    info "$package already installed"
  else
    brew install --cask "$package"
  fi
}

brew_trust_tap() {
  local tap="$1"

  if brew trust --help >/dev/null 2>&1; then
    brew trust --tap "$tap"
  fi
}

install_brew_packages() {
  log "Installing Homebrew packages"

  brew tap felixkratz/formulae
  brew tap koekeishiya/formulae
  brew tap manaflow-ai/cmux
  brew tap nikitabobko/tap
  brew_trust_tap felixkratz/formulae
  brew_trust_tap koekeishiya/formulae
  brew_trust_tap manaflow-ai/cmux
  brew_trust_tap nikitabobko/tap

  local -a formulae=(
    stow
    lazygit
    zoxide
    eza
    yazi
    ffmpeg
    sevenzip
    jq
    poppler
    fd
    ripgrep
    fzf
    imagemagick
    direnv
    fastfetch
    cloc
    dust
    macmon
    gh
    neovim
    bat
    uv
    terminal-notifier
    lua
    switchaudio-osx
    nowplaying-cli
    sketchybar
    skhd
    tmux
  )

  local -a casks=(
    mos
    pearcleaner
    font-jetbrains-mono-nerd-font
    font-maple-mono-nf-cn
    font-symbols-only-nerd-font
    sf-symbols
    font-sf-mono
    font-sf-pro
    cmux
    nikitabobko/tap/aerospace
  )

  local package
  for package in "${formulae[@]}"; do
    brew_install_formula "$package"
  done

  for package in "${casks[@]}"; do
    brew_install_cask "$package"
  done
}

remove_dotfiles_symlink() {
  local target_path="$1"
  local link_target

  [[ -L "$target_path" ]] || return 0
  link_target="$(stat -f "%Y" "$target_path" 2>/dev/null || true)"

  if [[ "${link_target#dotfiles/}" != "$link_target" || "${link_target#$DOTFILES_DIR/}" != "$link_target" ]]; then
    rm -f "$target_path"
  fi
}

cleanup_legacy_items() {
  log "Removing legacy Ollama, Hammerspoon, and yabai setup artifacts"

  if launchctl print "gui/$(id -u)/com.ollama.serve" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.ollama.serve.plist" >/dev/null 2>&1 \
      || launchctl unload "$HOME/Library/LaunchAgents/com.ollama.serve.plist" >/dev/null 2>&1 \
      || true
  fi

  if launchctl print "gui/$(id -u)/com.asmvik.yabai" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.asmvik.yabai.plist" >/dev/null 2>&1 \
      || launchctl remove com.asmvik.yabai >/dev/null 2>&1 \
      || true
  fi

  if launchctl print "gui/$(id -u)/com.koekeishiya.yabai" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.koekeishiya.yabai.plist" >/dev/null 2>&1 \
      || launchctl remove com.koekeishiya.yabai >/dev/null 2>&1 \
      || true
  fi

  rm -f "$HOME/Library/LaunchAgents/com.ollama.serve.plist"
  rm -f "$HOME/Library/LaunchAgents/com.asmvik.yabai.plist"
  rm -f "$HOME/Library/LaunchAgents/com.koekeishiya.yabai.plist"
  remove_dotfiles_symlink "$HOME/com.ollama.serve.plist"
  remove_dotfiles_symlink "$HOME/.yabairc"
  remove_dotfiles_symlink "$HOME/.hammerspoon"
  remove_dotfiles_symlink "$HOME/setup.sh"
  sudo_run rm -f /private/etc/sudoers.d/yabai

  osascript -e 'tell application "Hammerspoon" to quit' >/dev/null 2>&1 || true
  killall Hammerspoon >/dev/null 2>&1 || true

  if brew list --formula ollama >/dev/null 2>&1; then
    HOMEBREW_NO_INSTALL_CLEANUP=1 brew uninstall ollama
  fi

  if brew list --formula yabai >/dev/null 2>&1; then
    HOMEBREW_NO_INSTALL_CLEANUP=1 brew uninstall yabai
  fi

  if brew list --cask hammerspoon >/dev/null 2>&1; then
    HOMEBREW_NO_INSTALL_CLEANUP=1 brew uninstall --cask hammerspoon
  fi
}

link_dotfiles() {
  log "Linking dotfiles with Stow"

  stow --adopt --target="$HOME" --ignore='^README\.md$' --ignore='^setup\.sh$' .
}

install_nvm_node() {
  log "Installing nvm and Node"

  export NVM_DIR="$HOME/.nvm"

  local brew_prefix
  brew_prefix="$(brew --prefix 2>/dev/null || true)"
  if [[ -n "$brew_prefix" && -x "$brew_prefix/bin/npm" ]] \
    && "$brew_prefix/bin/npm" list -g opencommit --depth=0 >/dev/null 2>&1; then
    "$brew_prefix/bin/npm" uninstall -g opencommit
  fi

  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    PROFILE=/dev/null /bin/bash -c "set -euo pipefail; curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"
  else
    info "nvm already installed"
  fi

  set +u
  . "$NVM_DIR/nvm.sh"

  local installed_node_version
  if [[ "$NODE_VERSION" == "lts/*" ]]; then
    nvm install --lts
    installed_node_version="$(nvm version 'lts/*')"
  else
    nvm install "$NODE_VERSION"
    installed_node_version="$(nvm version "$NODE_VERSION")"
  fi

  if [[ "$installed_node_version" == "N/A" ]]; then
    printf "Failed to resolve installed Node version for %s\n" "$NODE_VERSION" >&2
    exit 1
  fi

  nvm alias default "$installed_node_version"
  nvm use "$installed_node_version"

  local node_bin
  local npm_bin
  node_bin="$(nvm which "$installed_node_version")"
  npm_bin="${node_bin:h}/npm"
  "$npm_bin" install -g opencommit@latest
  set -u
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

  mkdir -p "$HOME/Library/Fonts"

  local app_font="$HOME/Library/Fonts/sketchybar-app-font.ttf"
  if [[ ! -f "$app_font" ]]; then
    curl -fsSL https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v2.0.28/sketchybar-app-font.ttf \
      -o "$app_font"
  fi

  if [[ -f "$HOME/.local/share/sketchybar_lua/sketchybar.so" ]]; then
    info "SbarLua already installed"
    return 0
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  git clone --depth=1 https://github.com/FelixKratz/SbarLua.git "$tmp_dir"
  make -C "$tmp_dir" install
  rm -rf "$tmp_dir"
}

install_tmux_plugins() {
  log "Installing tmux plugins"

  local tpm_dir="$HOME/.tmux/plugins/tpm"
  if [[ ! -d "$tpm_dir/.git" ]]; then
    git clone --depth=1 https://github.com/tmux-plugins/tpm "$tpm_dir"
  fi

  /bin/bash "$tpm_dir/scripts/install_plugins.sh"
}

accept_xcode_license() {
  log "Accepting Xcode license"

  if have xcodebuild; then
    sudo_run xcodebuild -license accept
  fi
}

restart_services() {
  log "Restarting AeroSpace, skhd, and sketchybar"

  if have sketchybar; then
    brew services restart sketchybar || brew services start sketchybar
  fi

  if have aerospace; then
    open -g -a AeroSpace || skip "Could not open AeroSpace."
    sleep 1
    aerospace reload-config --no-gui || skip "Could not reload AeroSpace config."
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
  ensure_sudo
  require_command_line_tools
  setup_system_preferences
  install_homebrew
  install_brew_packages
  cleanup_legacy_items
  link_dotfiles
  install_nvm_node
  install_kitty
  install_cmux_cli
  install_sketchybar_assets
  install_tmux_plugins
  accept_xcode_license
  restart_services
  print_summary
}

main "$@"
