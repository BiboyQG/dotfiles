# My dotfiles

This repo contains the dotfiles for my MacOS system

## Requirements

Ensure you have the following installed on your system

### Stow 

```
brew install stow
```

## Install

First, pull the repo and enter the folder

```
git clone git@github.com:BiboyQG/dotfiles.git && cd dotfiles
```

Next, use Stow to create symlinks

```
stow .
```

### Tips

#### tmux

When installing tmux, run the following command:

```
mkdir -p ~/.tmux/plugins $$ git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

#### yabai

First you need to start the yabai:

```
yabai --start-service
```

Then run the following command before rebooting:

```
sudo nvram boot-args=-arm64e_preview_abi
```

Now you are good to go!
