# My dotfiles

This repo contains the dotfiles for my MacOS system.

## Tools

Most tools are installed by `setup.sh` via Homebrew (and a few via `npm`/`git`).

| Tool                | Install                  | Description                                      |
| ------------------- | ------------------------ | ------------------------------------------------ |
| Homebrew            | `brew`                   | Package manager for macOS                        |
| GNU Stow            | `brew`                   | Symlink manager for dotfiles                     |
| Kitty               | `brew --cask`            | GPU-based terminal emulator                      |
| Zsh                 | macOS                    | Shell and interactive environment                |
| Neovim              | `brew`                   | Vim-based text editor (`nvim`)                   |
| Tmux                | `brew`                   | Terminal multiplexer                             |
| Tmux Plugin Manager | `git`                    | Tmux plugin manager (`tpm`)                      |
| Agent tracker       | `setup_agent_tracker.sh` | Local tracker for tmux/Codex integration         |
| Sketchybar          | `brew`                   | macOS status bar replacement                     |
| Lua                 | `brew`                   | Runtime for Sketchybar scripting                 |
| SwitchAudioSource   | `brew`                   | Switch macOS audio devices (`SwitchAudioSource`) |
| NowPlaying CLI      | `brew`                   | Now Playing metadata (for Sketchybar)            |
| SbarLua             | `git`                    | Lua API for Sketchybar                           |
| Yabai               | `brew`                   | Tiling window manager for macOS                  |
| Skhd                | `brew`                   | Hotkey daemon for macOS                          |
| Hammerspoon         | `brew --cask`            | macOS automation tool (Lua)                      |
| Yazi                | `brew`                   | Terminal file manager                            |
| Lazygit             | `brew`                   | Terminal UI for git operations                   |
| Eza                 | `brew`                   | Modern `ls` replacement                          |
| Zoxide              | `brew`                   | Smarter `cd` replacement                         |
| Direnv              | `brew`                   | Per-directory environment loader                 |
| Ripgrep             | `brew`                   | Fast text search (`rg`)                          |
| Fzf                 | `brew`                   | Fuzzy finder                                     |
| Fd                  | `brew`                   | Fast `find` alternative                          |
| Jq                  | `brew`                   | JSON processor                                   |
| 7zip                | `brew`                   | Archive tool (`7zz`)                             |
| FFmpeg              | `brew`                   | Media toolkit                                    |
| ImageMagick         | `brew`                   | Image processing tools                           |
| Poppler             | `brew`                   | PDF utilities (`pdfinfo`, `pdftotext`, ...)      |
| Bat                 | `brew`                   | `cat` replacement with syntax highlighting       |
| Gh                  | `brew`                   | GitHub CLI                                       |
| Fastfetch           | `brew`                   | System info summary                              |
| Cloc                | `brew`                   | Count lines of code                              |
| Dust                | `brew`                   | `du` alternative                                 |
| Macmon              | `brew`                   | System monitor (TUI)                             |
| Terminal-notifier   | `brew`                   | Send macOS notifications from CLI                |
| Mos                 | `brew --cask`            | Smooth mouse/scroll wheel tuning                 |
| Pearcleaner         | `brew --cask`            | App uninstaller + leftover cleanup               |
| Ollama              | `brew`                   | Local LLM runner                                 |
| OpenCommit          | `npm -g`                 | LLM-assisted commit messages (`oco`)             |
| Uv                  | `brew`                   | Python package/venv manager                      |

> [!IMPORTANT]
>
> Please disable SIP before running the setup script.

Before everything, shut down your Mac and hold the power button for a while to boot into recovery mode.

Then, run the following command to disable SIP:

```bash
csrutil disable
```

Then, intall nvm if needed.

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
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
