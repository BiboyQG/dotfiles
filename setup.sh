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

# Check if Xcode is installed before trying to install command line tools
if ! xcode-select -p &>/dev/null; then
    echo "Installing commandline tools..."
    xcode-select --install
else
    echo "Xcode command line tools already installed"
fi

if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "Homebrew already installed"
fi

# install stow
brew install stow

# delete existing dotfiles
rm -rf $HOME/.config $HOME/.tmux.conf $HOME/.skhdrc $HOME/.yabairc $HOME/.zshrc $HOME/.hammerspoon

# create symlinks of my dotfiles (will override if exists)
echo "Creating symlinks"
stow --adopt .

# install other dependencies
echo "Installing Dependencies using Homebrew"
[ -x "$(command -v lazygit)" ] || brew install jesseduffield/lazygit/lazygit
[ -x "$(command -v zoxide)" ] || brew install zoxide
[ -x "$(command -v eza)" ] || brew install eza
[ -x "$(command -v yazi)" ] || brew install yazi ffmpeg sevenzip jq poppler fd ripgrep fzf imagemagick font-symbols-only-nerd-font
[ -x "$(command -v direnv)" ] || brew install direnv
[ -x "$(command -v fastfetch)" ] || brew install fastfetch
[ -x "$(command -v cloc)" ] || brew install cloc
[ -x "$(command -v dust)" ] || brew install dust
[ -x "$(command -v asitop)" ] || brew install asitop
[ -x "$(command -v gh)" ] || brew install gh
brew install appcleaner
brew install hammerspoon
brew install --cask mos

# install fonts for terminal
brew install --cask font-jetbrains-mono-nerd-font
brew install --cask font-maple-mono-nf-cn

echo "Installing Dependencies for Sketchybar"
# Packages
brew install lua
brew install switchaudio-osx
brew install nowplaying-cli

# accept xcode license
sudo xcodebuild -license accept

# install sketchybar
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
brew install koekeishiya/formulae/skhd

# install tmux and tmux plugin manager
brew install tmux
echo "Installing Tmux Plugin Manager"
mkdir -p ~/.tmux/plugins && git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# install yabai
brew install koekeishiya/formulae/yabai

# configure yabai
sudo nvram boot-args=-arm64e_preview_abi
echo "IMPORTANT: Follow the following instructions to configure yabai:"
echo "sudo visudo /etc/sudoers"
echo "Defaults	env_keep += \"TERMINFO\""
echo "'$(whoami) ALL = (root) NOPASSWD: sha256:$(shasum -a 256 $(which yabai) | awk "{print \$1;}") $(which yabai) --load-sa' to '/private/etc/sudoers.d/yabai'"
echo "After that, reboot and run: sudo yabai --load-sa"

# start services
echo "Starting Services (grant permissions)..."
skhd --start-service
yabai --start-service
brew services start sketchybar

echo "Installation would be completed once you've done the above steps!"
