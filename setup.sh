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

# Check if Xcode is installed before trying to install command line tools
if ! xcode-select -p &>/dev/null; then
    echo "Installing commandline tools..."
    xcode-select --install
else
    echo "Xcode command line tools already installed"
fi

# Install mas
brew install mas

# Install Xcode
mas install 497799835

# create symlinks of my dotfiles (will override if exists)
echo "Creating symlinks"
# Create .config directory if it doesn't exist and set permissions
mkdir -p "$HOME/.config"
chmod 755 "$HOME/.config"

# Handle .config directory contents
if [ -d "$HOME/.config" ]; then
    # Copy contents instead of symlink if permission issues
    cp -R "$HOME/dotfiles/.config/"* "$HOME/.config/" || {
        echo "Warning: Could not copy .config contents. You may need to copy files manually."
    }
else
    echo "Warning: Could not create .config directory"
fi

# Continue with other symlinks
ln -sf $HOME/dotfiles/.tmux.conf $HOME/.tmux.conf
ln -sf $HOME/dotfiles/.skhdrc $HOME/.skhdrc
ln -sf $HOME/dotfiles/.yabairc $HOME/.yabairc
ln -sf $HOME/dotfiles/.zshrc $HOME/.zshrc
ln -sf $HOME/dotfiles/.gitconfig $HOME/.gitconfig
ln -sf $HOME/dotfiles/OpenArcWindow.scpt $HOME/OpenArcWindow.scpt

# install dependencies
echo "Installing Dependencies using Homebrew"
[ -x "$(command -v lazygit)" ] || brew install jesseduffield/lazygit/lazygit
[ -x "$(command -v zoxide)" ] || brew install zoxide
[ -x "$(command -v eza)" ] || brew install eza
[ -x "$(command -v yazi)" ] || brew install yazi ffmpeg sevenzip jq poppler fd ripgrep fzf imagemagick font-symbols-only-nerd-font
[ -x "$(command -v direnv)" ] || brew install direnv

# install fonts for terminal
brew install --cask font-jetbrains-mono-nerd-font
brew install --cask font-maple-mono-nf-cn

echo "Installing Dependencies for Sketchybar"
# Packages
brew install lua
brew install switchaudio-osx
brew install nowplaying-cli

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

# install tmux plugin manager
echo "Installing Tmux Plugin Manager"
mkdir -p ~/.tmux/plugins && git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# install yabai
brew install koekeishiya/formulae/yabai

# configure yabai
yabai --start-service
sudo nvram boot-args=-arm64e_preview_abi
echo "Please add TERM manually"
echo "After that, run yabai --load-sa"

# start services
echo "Starting Services (grant permissions)..."
brew services start skhd
brew services start yabai
brew services start sketchybar

echo "(optional) Add sudoer manually:\n '$(whoami) ALL = (root) NOPASSWD: sha256:$(shasum -a 256 $(which yabai) | awk "{print \$1;}") $(which yabai) --load-sa' to '/private/etc/sudoers.d/yabai'"
echo "Installation complete...\n"