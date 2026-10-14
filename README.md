# My dotfiles

English · [简体中文](README.zh-CN.md)

Personal dotfiles for **Apple Silicon macOS**. Intel Macs are not supported.

A Zsh, Kitty, tmux, and Neovim environment with AeroSpace window management, SketchyBar, Yazi, and VS Code settings. Files in [`home/`](home/) are deployed with GNU Stow; [`Brewfile`](Brewfile) and [`setup.sh`](setup.sh) manage dependencies.

## Quick start

```sh
xcode-select --install   # once, if the Command Line Tools are missing
git clone git@github.com:BiboyQG/dotfiles.git
cd dotfiles
zsh setup.sh --skip-system-defaults
```

Setup installs or updates tools, links configurations, and restarts or reloads OpenUsage, AeroSpace, and SketchyBar. To also apply macOS defaults and NVRAM preferences, run `zsh setup.sh`.

## Checks

```sh
zsh check.sh          # Deterministic checks and isolated deployment simulations
zsh check.sh --live   # Also inspect installed tools and the current machine
```

## Documentation

- [Setup and maintenance](docs/setup.md): installation details, configuration layout, local overrides, and troubleshooting.
- [Everyday usage](docs/usage.md): tmux session slots, keyboard shortcuts, and shell helpers.
- [Tools](docs/tools.md): package inventory and installation methods.
- Agent configuration: [`home/.claude/`](home/.claude/) (Claude Code `CLAUDE.md` and `settings.json`) and [`home/.codex/AGENTS.md`](home/.codex/AGENTS.md), linked into `~/.claude` and `~/.codex`.
