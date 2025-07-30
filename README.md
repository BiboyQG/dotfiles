# My dotfiles

This repo contains the dotfiles for my MacOS system.

## Tools

| Tool       | Version | Description                                           |
| ---------- | ------- | ----------------------------------------------------- |
| kitty      | 0.37.0  | Fast, feature-rich, GPU-based terminal emulator       |
| zsh        | N/A     | Modern shell with advanced features and customization |
| nvim       | N/A     | Highly extensible Vim-based text editor               |
| sketchybar | N/A     | Highly customizable macOS status bar replacement      |
| yabai      | N/A     | Tiling window manager for macOS                       |
| skhd       | N/A     | Simple hotkey daemon for macOS                        |
| tmux       | 3.5a    | Terminal multiplexer for multiple sessions            |
| yazi       | N/A     | Rust-based terminal file manager for macOS            |
| lazygit    | N/A     | Simple terminal UI for git operations                 |
| hammerspoon| N/A     | Powerful automation tool for macOS (auto-switch input source) |
| fastfetch  | N/A     | Fastfetch is a fast alternative to neofetch for macOS |
| cloc       | N/A     | Count lines of code                                   |

> [!IMPORTANT]
>
> Please disable SIP before running the setup script.

Before everything, shut down your Mac and hold the power button for a while to boot into recovery mode.

Then, run the following command to disable SIP:

```bash
csrutil disable
```

Then, intall homebrew, nvm and miniforge.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
```

```bash
curl https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-arm64.sh | sh
```

Then, pull the repo and enter the folder

```bash
git clone git@github.com:BiboyQG/dotfiles.git && cd dotfiles
```

Next, we run the setup script

```bash
zsh setup_1.sh
zsh setup_2.sh
zsh setup_3.sh
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

```bash
echo "$(whoami) ALL=(root) NOPASSWD: sha256:$(shasum -a 256 $(which yabai) | cut -d " " -f 1) $(which yabai) --load-sa" | sudo tee /private/etc/sudoers.d/yabai
```

#### Start services

```bash
brew services start sketchybar
skhd --restart-service
sudo yabai --load-sa
```

You are all set!
