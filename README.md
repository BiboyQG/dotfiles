# My dotfiles

This repo contains the dotfiles for my Apple Silicon Mac. Intel Macs are not supported.

Files deployed into the home directory live under the dedicated `home/` Stow package. Repository tooling such as `setup.sh`, `check.sh`, and `Brewfile` stays at the repository root.

Powerlevel10k, Neovim, and Yazi state that affects reproducibility is tracked in `home/.p10k.zsh`, `home/.config/nvim/lazy-lock.json`, and `home/.config/yazi/package.toml`. Machine-specific login-shell additions belong in the untracked `~/.zprofile.local`, which is sourced after the managed `home/.zprofile`.

## Tools

Most tools are declared in `Brewfile`; `setup.sh` also installs the latest non-Homebrew dependencies.

| Tool                | Install                  | Description                                      |
| ------------------- | ------------------------ | ------------------------------------------------ |
| Homebrew            | `brew`                   | Package manager for macOS                        |
| GNU Stow            | `brew`                   | Symlink manager for dotfiles                     |
| Git                 | `brew`                   | Version control (`git`)                          |
| Kitty               | official installer       | GPU-based terminal emulator                      |
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
| Yq                  | `brew`                   | YAML/TOML processor                              |
| Json5               | `brew`                   | JSON5 validator used by `check.sh`               |
| 7zip                | `brew`                   | Archive tool (`7zz`)                             |
| FFmpeg              | `brew`                   | Media toolkit                                    |
| ImageMagick         | `brew`                   | Image processing tools                           |
| Poppler             | `brew`                   | PDF utilities (`pdfinfo`, `pdftotext`, ...)      |
| Resvg               | `brew`                   | SVG rasterizer (Yazi previews)                   |
| Fontconfig          | `brew`                   | Font query tools used by `check.sh --live`       |
| Tree-sitter CLI     | `brew`                   | Parser tooling used by `check.sh --live`         |
| Python              | `brew`                   | Runtime for tmux helpers and editor tooling       |
| Bat                 | `brew`                   | `cat` replacement with syntax highlighting       |
| Gh                  | `brew`                   | GitHub CLI                                       |
| Fastfetch           | `brew`                   | System info summary                              |
| Cloc                | `brew`                   | Count lines of code                              |
| Dust                | `brew`                   | `du` alternative                                 |
| Macmon              | `brew`                   | System monitor (TUI)                             |
| Terminal-notifier   | `brew`                   | Send macOS notifications from CLI                |
| Mos                 | `brew --cask`            | Smooth mouse/scroll wheel tuning                 |
| Pearcleaner         | `brew --cask`            | App uninstaller + leftover cleanup               |
| Fonts               | `brew --cask`            | JetBrains Mono NF, Monaspace, Maple Mono NF CN, Symbols Nerd Font, SketchyBar app font, SF Mono, SF Pro, SF Symbols |
| Uv                  | `brew`                   | Python package/venv manager                      |
| VS Code             | `brew --cask`            | GUI editor with extensions declared in Brewfile  |
| Arc                 | `brew --cask`            | Browser used by the AeroSpace shortcut           |
| PDF Expert          | `brew --cask`            | PDF opener used by Yazi                          |
| Claude Code         | `brew --cask`            | Anthropic coding CLI                             |
| Codex CLI           | `npm`                    | OpenAI coding CLI                                |

AeroSpace is used for window management, so SIP can stay enabled.

Then, pull the repo and enter the folder

```bash
git clone git@github.com:BiboyQG/dotfiles.git && cd dotfiles
```

Next, we run the setup script

```bash
zsh setup.sh
```

To install the tools and links without changing macOS defaults or NVRAM values:

```bash
zsh setup.sh --skip-system-defaults
```

This will:

- Check Stow, tmux plugin, existing Brew tap, and any running AeroSpace configuration conflicts before changing system settings or installing anything; a stopped AeroSpace instance is validated immediately after launch
- Symlink the dotfiles without adopting existing files
- Preserve an existing untracked `.zprofile` as `.zprofile.local` before linking the managed login profile
- Install or upgrade the Homebrew bundle and validate trusted taps
- Keep existing unmanaged Arc and VS Code apps instead of requiring Homebrew to adopt them
- Install the latest kitty release with the official installer
- Install or update nvm, Node, Codex CLI, zinit, SbarLua, the Yazi flavor, and tmux plugins to their latest upstream versions
- Install declared VS Code extensions and pre-install zsh and Neovim plugins
- Deploy VS Code settings and keybindings into `~/Library/Application Support/Code/User` through the Stow package
- Keep machine-local Codex config outside the repo
- Build SketchyBar helpers into `~/.local/libexec/sketchybar`, then restart OpenUsage and AeroSpace, wait for AeroSpace to become ready, and restart SketchyBar and skhd with postflight checks

Run the repository checks without installing or upgrading anything:

```bash
zsh check.sh
```

The default checker validates shell, Lua, Python, TOML, JSON/JSONC, setup preflight isolation, the LaunchAgent, deterministic IP/media/SketchyBar fixtures, strict C builds/static analysis, tracked `home/` package boundaries, and clean Stow simulations.

Run read-only checks that depend on the current machine state:

```bash
zsh check.sh --live
```

Live mode additionally validates installed Kitty fonts, Neovim Tree-sitter parsers and queries, the active AeroSpace config, an isolated tmux server, and the Brew bundle. Its Brew cleanup audit only reports undeclared dependencies; it never passes `--force` or removes them.

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

To make our life easier, some useful aliases are defined in `home/.zshrc`:

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
