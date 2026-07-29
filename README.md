# My dotfiles

This repo contains the dotfiles for my MacOS system.

## Tools

Most tools are declared in `Brewfile`; `setup.sh` also installs the pinned non-Homebrew dependencies.

| Tool                | Install                  | Description                                      |
| ------------------- | ------------------------ | ------------------------------------------------ |
| Homebrew            | `brew`                   | Package manager for macOS                        |
| GNU Stow            | `brew`                   | Symlink manager for dotfiles                     |
| Kitty               | official installer       | GPU-based terminal emulator                      |
| cmux                | `brew --cask`            | Native macOS terminal for AI coding agents       |
| Zsh                 | macOS                    | Shell and interactive environment                |
| Neovim              | `brew`                   | Vim-based text editor (`nvim`)                   |
| Tmux                | `brew`                   | Terminal multiplexer                             |
| Tmux Plugin Manager | `git`                    | Tmux plugin manager (`tpm`)                      |
| Sketchybar          | `brew`                   | macOS status bar replacement                     |
| Lua                 | `brew`                   | Runtime for Sketchybar scripting                 |
| SwitchAudioSource   | `brew`                   | Switch macOS audio devices (`SwitchAudioSource`) |
| NowPlaying CLI      | `brew`                   | Now Playing metadata (for Sketchybar)            |
| SbarLua             | `git`                    | Lua API for Sketchybar                           |
| AeroSpace           | `brew --cask`            | Tiling window manager for macOS                  |
| Skhd                | `brew`                   | Fallback for the AeroSpace enable/disable hotkey |
| OpenUsage           | `brew --cask`            | Local AI usage API and menu bar app              |
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
| Uv                  | `brew`                   | Python package/venv manager                      |

AeroSpace is used for window management, so SIP can stay enabled.

Then, pull the repo and enter the folder

```bash
git clone git@github.com:BiboyQG/dotfiles.git && cd dotfiles
```

Next, we run the setup script

```bash
zsh setup.sh
```

This will:

- Check for Stow conflicts, then symlink the dotfiles without adopting existing files
- Install the pinned Homebrew bundle and validate trusted taps
- Install kitty with the official installer
- Install pinned nvm, Node, zinit, SbarLua, and tmux plugins
- Link VS Code settings to its real macOS user-config directory
- Keep machine-local Codex config and generated Zed prompt data outside the repo
- Build SketchyBar helpers, then restart OpenUsage, AeroSpace, skhd, and SketchyBar

### Tips

#### tmux

Some tmux behavior in this repo is optimized for “session slots” (fast switching / moving windows):

- Sessions are auto-renamed to `<index>-<label>` (example: `1-dot`, `2-spreadsheet-build`)
- Rename the current session label with `<prefix> + .` (the prompt omits the numeric prefix)
- Create a new session with `Ctrl+s` (keeps numbering contiguous)
- Switch sessions with `F1..F10` (in Kitty, `⌘1..⌘0` sends `F1..F10` to tmux)
- Move the current window to session slot with `<prefix> + 1..0`

Shell helpers:

- `ta <label>` attaches by label (example: `ta dot` attaches to `1-dot`)
- `ta <idx>` attaches by slot (example: `ta 1`)
- `tls` lists sessions

#### zsh

`Ctrl+s` is bound in tmux, so XON/XOFF is disabled in interactive shells to avoid terminal “freezing”.

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
