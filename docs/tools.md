# Tools

[English README](../README.md) · [中文 README](../README.zh-CN.md)

The package manifest is [Brewfile](../Brewfile); native installers and plugin updates are implemented in [setup.sh](../setup.sh). This inventory summarizes their roles.

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
| hf                  | `brew`                   | Hugging Face Hub CLI                             |
| Mole                | `brew`                   | Deep clean and optimize macOS                    |
| Terminal-notifier   | `brew`                   | Send macOS notifications from CLI                |
| Mos                 | `brew --cask`            | Smooth mouse/scroll wheel tuning                 |
| Pearcleaner         | `brew --cask`            | App uninstaller + leftover cleanup               |
| Fonts               | `brew --cask`            | JetBrains Mono NF, Monaspace, Maple Mono NF CN, Symbols Nerd Font, SketchyBar app font, SF Mono, SF Pro, SF Symbols |
| Uv                  | `brew`                   | Python package/venv manager                      |
| VS Code             | `brew --cask`            | GUI editor with extensions declared in Brewfile  |
| Arc                 | `brew --cask`            | Browser used by the AeroSpace shortcut           |
| PDF Expert          | `brew --cask`            | PDF opener used by Yazi                          |
| Claude Code         | Native installer         | Anthropic coding CLI                             |
| Codex CLI           | Standalone installer     | OpenAI coding CLI                                |
