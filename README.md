# My dotfiles

This repo contains the dotfiles for my MacOS system.

## Tools

| Tool        | Version | Description                                                   |
| ----------- | ------- | ------------------------------------------------------------- |
| kitty       | 0.37.0  | Fast, feature-rich, GPU-based terminal emulator               |
| zsh         | N/A     | Modern shell with advanced features and customization         |
| nvim        | N/A     | Highly extensible Vim-based text editor                       |
| sketchybar  | N/A     | Highly customizable macOS status bar replacement              |
| yabai       | N/A     | Tiling window manager for macOS                               |
| skhd        | N/A     | Simple hotkey daemon for macOS                                |
| tmux        | 3.5a    | Terminal multiplexer for multiple sessions                    |
| yazi        | N/A     | Rust-based terminal file manager for macOS                    |
| lazygit     | N/A     | Simple terminal UI for git operations                         |
| hammerspoon | N/A     | Powerful automation tool for macOS (auto-switch input source) |
| fastfetch   | N/A     | Fastfetch is a fast alternative to neofetch for macOS         |
| cloc        | N/A     | Count lines of code                                           |
| dust        | N/A     | A more intuitive version of du in rust                        |
| asitop      | N/A     | System monitor for terminal                                   |
| gh          | N/A     | GitHub CLI                                                    |
| bat         | N/A     | Cat with wings                                                |
| oco         | N/A     | Generate commit messages with LLMs                            |
| uv          | N/A     | Rust package manager for Python                               |

> [!IMPORTANT]
>
> Please disable SIP before running the setup script.

Before everything, shut down your Mac and hold the power button for a while to boot into recovery mode.

Then, run the following command to disable SIP:

```bash
csrutil disable
```

Then, intall nvm and miniforge if needed.

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
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
zsh setup.sh
```

This will:

- Symlink the dotfiles into place (via `stow --adopt`)
- Install dependencies via Homebrew
- Set up the tmux agent-tracker integration (build binaries + start a brew service)

### Tips

#### yabai

You need to manually add the following line into `sudo visudo /etc/sudoers`:

```
Defaults	env_keep += "TERMINFO"
```

#### Start services

```bash
brew services start sketchybar
skhd --restart-service
sudo yabai --load-sa
```

#### tmux

Some tmux behavior in this repo is optimized for “session slots” (fast switching / moving windows):

- Sessions are auto-renamed to `<index>-<label>` (example: `1-dot`, `2-spreadsheet-build`)
- Rename the current session label with `<prefix> + .` (the prompt omits the numeric prefix)
- Create a new session with `Ctrl+s` (keeps numbering contiguous)
- Switch sessions with `F1..F10` (in Kitty, `⌘1..⌘0` sends `F1..F10` to tmux)
- Move the current window to session slot with `<prefix> + 1..0`
- Toggle the tmux agent-tracker UI with `F12` (in Kitty, `⌘t` sends `F12`)

Shell helpers:

- `ta <label>` attaches by label (example: `ta dot` attaches to `1-dot`)
- `ta <idx>` attaches by slot (example: `ta 1`)
- `tls` lists sessions

#### Agent tracker

This repo includes a lightweight “agent-tracker” used by tmux hooks and (optionally) Codex:

- `setup.sh` runs `setup_agent_tracker.sh` to build and install `~/.config/agent-tracker/bin/*` and start the `agent-tracker-server` brew service
- tmux hooks keep task state in sync on attach, pane focus, and pane exit
- If `~/.codex/config.toml` exists, the installer appends an MCP server entry so Codex can talk to the tracker

#### zsh

`Ctrl+s` is bound in tmux, so XON/XOFF is disabled in interactive shells to avoid terminal “freezing”.

#### Ollama LaunchAgent Setup

To ensure a good experience in WeChat auto reply, we made Ollama serve start automatically at boot and restart on crashes.

To stop the service: `launchctl unload ~/Library/LaunchAgents/com.ollama.serve.plist`

You are all set!

### Aliases

To make our life easier, some useful aliases are defined in `.zshrc`:

| Alias | Command          | Description                                  |
| ----- | ---------------- | -------------------------------------------- |
| ll    | eza -alh --icons | Enhanced file listing with icons and details |
| ssh   | kitten ssh       | SSH through Kitty terminal                   |
| s     | fastfetch        | System information display                   |
| l     | lazygit          | Terminal Git UI                              |
| t     | sudo asitop      | System monitor for macOS                     |
| y     | yazi function    | File manager with directory changing support |
| c     | claude           | Claude Code CLI                              |
| tn    | tmux new -s      | Create a new tmux session                    |
| ta    | ta <label\|idx>  | Attach to a tmux session                     |
| cat   | bat              | Cat with wings                               |

### Hammerspoon

Thanks to [Hammerspoon](https://www.hammerspoon.org/), I can easily create shortcuts for many functionality that improves our productivity.

#### Video Tutorial

[Bilibili](https://www.bilibili.com/video/BV1cHhPzCE11)

#### Shortcuts Description

| Shortcuts | Description                       |
| --------- | --------------------------------- |
| CMD + p   | Toggle ClashX.Meta Proxy          |
| CMD + g   | Toggle WeChat messages auto reply |
