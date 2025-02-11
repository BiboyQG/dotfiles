# My dotfiles

This repo contains the dotfiles for my MacOS system

## Requirements

Ensure you have the following installed on your system

### Stow 

```bash
brew install stow
```

## Install

Before everything, intall homebrew and miniforge.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

```bash
curl https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-arm64.sh | sh
```

Then, pull the repo and enter the folder

```bash
git clone git@github.com:BiboyQG/dotfiles.git && cd dotfiles
```

Next, use Stow to create symlinks

```bash
stow .
```

### Tips

#### yabai

You need to run the following command before rebooting:

```bash
sudo nvram boot-args=-arm64e_preview_abi
```

After that, you need to manually add the following line into `sudo visudo /etc/sudoers`:

```bash
Defaults	env_keep += "TERMINFO"
```

Now you are good to go!
