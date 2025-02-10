#!/bin/zsh

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

# Install xCode cli tools
echo "Installing commandline tools..."
xcode-select --install

# Install Xcode
mas install 497799835

# Install Miniforge
echo "Installing Python Packages..."
curl https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-arm64.sh | sh
# revert to not using base
conda config --set auto_activate_base false

# Install Brew
echo "Installing Brew..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew analytics off

# create symlinks of my dotfiles (will not override if already exists)
echo "Creating symlinks"
[ -d "$HOME/.config" ] && ln -s $HOME/dotfiles/.config/* $HOME/.config || ln -s $HOME/dotfiles/.config $HOME
[ -f "$HOME/.tmux.conf" ] || ln -s $HOME/dotfiles/.tmux.conf $HOME/.tmux.conf
[ -f "$HOME/.skhdrc" ] || ln -s $HOME/dotfiles/.skhdrc $HOME/.skhdrc
[ -f "$HOME/.yabairc" ] || ln -s $HOME/dotfiles/.yabairc $HOME/.yabairc
[ -f "$HOME/.zshrc" ] || ln -s $HOME/dotfiles/.zshrc $HOME/.zshrc
[ -f "$HOME/.gitconfig" ] || ln -s $HOME/dotfiles/.gitconfig $HOME/.gitconfig
[ -f "$HOME/OpenArcWindow.scpt" ] || ln -s $HOME/dotfiles/OpenArcWindow.scpt $HOME/OpenArcWindow.scpt

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