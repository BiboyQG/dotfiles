#!/bin/zsh

# Download and install Node.js:
nvm install 22
# Verify the Node.js version:
node -v # Should print "v22.14.0".
nvm current # Should print "v22.14.0".
# Download and install Yarn:
corepack enable yarn
# Verify Yarn version:
yarn -v