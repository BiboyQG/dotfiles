#!/bin/zsh
set -e  # Exit on error

echo "This script will set up your macOS system with various tools and configurations."
echo "Please make sure you have reviewed the script before proceeding."
read -q "REPLY?Do you want to continue? (y/n) "
echo    # move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 1
fi

# Check if System Integrity Protection (SIP) is disabled
if csrutil status | grep -q "System Integrity Protection status: disabled"; then
    echo "SIP is disabled, continuing..."
else
    echo "SIP is enabled. To disable it:"
    echo "1. Restart your Mac and hold start button during startup to enter Recovery Mode"
    echo "2. Open Terminal from Utilities menu"
    echo "3. Run: csrutil disable"
    echo "4. Restart your Mac"
    exit 1
fi

echo "Setting up system preferences..."

# Close any open System Preferences panes, to prevent them from overriding
# settings we’re about to change
osascript -e 'tell application "System Preferences" to quit'

# Ask for the administrator password upfront
sudo -v

# Enable three finger drag
defaults write com.apple.AppleMultitouchTrackpad "TrackpadThreeFingerDrag" -bool "true"

# Disable the “Are you sure you want to open this application?” dialog
defaults write com.apple.LaunchServices LSQuarantine -bool false

# Disable automatic capitalization as it’s annoying when typing code
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

# Disable smart dashes as they’re annoying when typing code
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# Disable automatic period substitution as it’s annoying when typing code
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

# Disable smart quotes as they’re annoying when typing code
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

# Disable auto-correct
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# Set a blazingly fast keyboard repeat rate
defaults write NSGlobalDomain KeyRepeat -int 1
defaults write NSGlobalDomain InitialKeyRepeat -int 20

# Remove the sleep image file to save disk space
sudo rm -rf /private/var/vm/sleepimage
# Create a zero-byte file instead…
sudo touch /private/var/vm/sleepimage
# …and make sure it can’t be rewritten
sudo chflags uchg /private/var/vm/sleepimage

# Finder: show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Finder: show status bar
defaults write com.apple.finder ShowStatusBar -bool true

# Finder: show path bar
defaults write com.apple.finder ShowPathbar -bool true

# Display full POSIX path as Finder window title
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# Keep folders on top when sorting by name
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# When performing a search, search the current folder by default
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Disable the warning when changing a file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Enable spring loading for directories
defaults write NSGlobalDomain com.apple.springing.enabled -bool true

# Remove the spring loading delay for directories
defaults write NSGlobalDomain com.apple.springing.delay -float 0

# Avoid creating .DS_Store files on network or USB volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Disable disk image verification
defaults write com.apple.frameworks.diskimages skip-verify -bool true
defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true

# Automatically open a new Finder window when a volume is mounted
defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true
defaults write com.apple.frameworks.diskimages auto-open-rw-root -bool true
defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true

# Use list view in all Finder windows by default
# Four-letter codes for the other view modes: `icnv`, `clmv`, `glyv`
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Disable the warning before emptying the Trash
defaults write com.apple.finder WarnOnEmptyTrash -bool false

# Automatically hide and show the Dock
defaults write com.apple.dock autohide -bool true

# Disable startup sound and any other sound effects on boot
sudo nvram StartupMute=%01
sudo nvram SystemAudioVolume=' '

echo "Setting up xcode-select..."

# Check if Xcode is installed before trying to install command line tools
if ! xcode-select -p &>/dev/null; then
    echo "Installing commandline tools..."
    xcode-select --install
else
    echo "Xcode command line tools already installed"
fi

# install homebrew
if ! command -v brew &>/dev/null; then
  echo
  echo -e "$>>>>>>>>>>>>>>>>>>>>>>>>>>"
  echo "Installing Homebrew"
  echo "Enter your password below (if required)"
  # Only install brew if not installed yet
  echo
  echo -e ">>>>>>>>>>>>>>>>>>>>>>>>>>"
  # Install Homebrew
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  echo
  echo -e "Homebrew installed successfully."
else
  echo
  echo -e "Homebrew is already installed."
fi

# After brew is installed, we need to configure our shell for homebrew
echo
echo -e ">>>>>>>>>>>>>>>>>>>>>>>>>>"
echo "Modifying .zprofile file"
CHECK_LINE='eval "$(/opt/homebrew/bin/brew shellenv)"'
BIN_PATH_LINE='export PATH="$HOME/bin:$PATH"'

# File to be checked and modified
FILE="$HOME/.zprofile"

# Check if the specific line exists in the file
if grep -Fq "$CHECK_LINE" "$FILE"; then
  echo "Content already exists in $FILE"
else
  # Append the content if it does not exist
  echo -e '\n# Configure shell for brew\n'"$CHECK_LINE" >>"$FILE"
  echo "Content added to $FILE"
fi

# Ensure ~/bin is on PATH (for scripts like myip)
if grep -Fq "$BIN_PATH_LINE" "$FILE"; then
  echo "Content already exists in $FILE"
else
  echo -e '\n# Add ~/bin to PATH\n'"$BIN_PATH_LINE" >>"$FILE"
  echo "Content added to $FILE"
fi

# After adding it to the .zprofile file, make sure to run the command
source $FILE

# install stow
echo "Installing Stow"
brew install stow

# delete existing dotfiles
rm -rf $HOME/.config $HOME/.tmux.conf $HOME/.skhdrc $HOME/.yabairc $HOME/.zshrc $HOME/.hammerspoon

# create symlinks of my dotfiles (will override if exists)
echo "Creating symlinks..."
stow --adopt .

# setup agent tracker
echo "Setting up agent tracker..."
bash ./setup_agent_tracker.sh

# install other dependencies
echo "Installing other dependencies using Homebrew..."
[ -x "$(command -v lazygit)" ] || brew install jesseduffield/lazygit/lazygit
[ -x "$(command -v zoxide)" ] || brew install zoxide
[ -x "$(command -v eza)" ] || brew install eza
[ -x "$(command -v yazi)" ] || brew install yazi ffmpeg sevenzip jq poppler fd ripgrep fzf imagemagick font-symbols-only-nerd-font
[ -x "$(command -v direnv)" ] || brew install direnv
[ -x "$(command -v fastfetch)" ] || brew install fastfetch
[ -x "$(command -v cloc)" ] || brew install cloc
[ -x "$(command -v dust)" ] || brew install dust
[ -x "$(command -v macmon)" ] || brew install macmon
[ -x "$(command -v gh)" ] || brew install gh
[ -x "$(command -v nvim)" ] || brew install neovim
[ -x "$(command -v bat)" ] || brew install bat
[ -x "$(command -v uv)" ] || brew install uv
[ -x "$(command -v terminal-notifier)" ] || brew install terminal-notifier
brew install pearcleaner
brew install hammerspoon
brew install --cask mos

# install fonts for terminal
brew install --cask font-jetbrains-mono-nerd-font
brew install --cask font-maple-mono-nf-cn

echo "Installing dependencies for Sketchybar..."
# Packages
brew install lua
brew install switchaudio-osx
brew install nowplaying-cli

# accept xcode license
sudo xcodebuild -license accept

# install sketchybar
echo "Installing Sketchybar..."
brew tap FelixKratz/formulae
brew install sketchybar

# Fonts
brew install --cask sf-symbols
brew install --cask font-sf-mono
brew install --cask font-sf-pro

curl -L https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v2.0.28/sketchybar-app-font.ttf -o $HOME/Library/Fonts/sketchybar-app-font.ttf

# SbarLua
(git clone https://github.com/FelixKratz/SbarLua.git /tmp/SbarLua && cd /tmp/SbarLua/ && make install && rm -rf /tmp/SbarLua/)

# install skhd
echo "Installing skhd..."
brew install koekeishiya/formulae/skhd

# install tmux and tmux plugin manager
echo "Installing tmux..."
brew install tmux
echo "Installing Tmux Plugin Manager"
mkdir -p ~/.tmux/plugins && git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# run script to download all plugins for tmux
bash ~/.tmux/plugins/tpm/scripts/install_plugins.sh

# install yabai
echo "Installing yabai..."
brew install koekeishiya/formulae/yabai

# configure yabai
sudo nvram boot-args=-arm64e_preview_abi
echo "IMPORTANT: Follow the following instructions to configure yabai:"
echo "sudo visudo /etc/sudoers"
echo "Defaults	env_keep += \"TERMINFO\""
echo "$(whoami) ALL=(root) NOPASSWD: sha256:$(shasum -a 256 $(which yabai) | cut -d " " -f 1) $(which yabai) --load-sa" | sudo tee /private/etc/sudoers.d/yabai
echo "After that, reboot and run: sudo yabai --load-sa"

# start services
echo "Starting Services (grant permissions)..."
skhd --start-service
yabai --start-service
brew services start sketchybar

# ollama setup
echo "Installing ollama..."
brew install ollama
cp com.ollama.serve.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.ollama.serve.plist
ollama pull qwen2.5:14b

# oco setup
npm i -g opencommit@latest
oco config set OCO_AI_PROVIDER='ollama' OCO_MODEL='qwen2.5:14b' OCO_API_URL=http://localhost:11434/api/chat OCO_ONE_LINE_COMMIT=true

echo "Installation would be completed once you've done the above steps!"
