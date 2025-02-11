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

# Install mas and stow
brew install mas stow

# Install Xcode
mas install 497799835

