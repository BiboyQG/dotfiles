# Setup and maintenance

[English README](../README.md) · [中文 README](../README.zh-CN.md)

## Install or update

Run the commands in the [README quick start](../README.md#quick-start); to update an existing clone, run `git pull` and then `zsh setup.sh --skip-system-defaults` in it. Setup exits when the Xcode Command Line Tools are missing.

With `--skip-system-defaults`, setup asks for an administrator password only to install Homebrew, accept a pending Xcode license, or install or upgrade the pkg-based casks (SF Symbols, SF Mono, SF Pro). Run `zsh setup.sh` without the flag once on each Mac: its defaults step turns off the input-source indicator, which otherwise stalls AeroSpace on every switch LockIME makes.

Neovim plugins and the Yazi flavor are installed at the revisions pinned in [`lazy-lock.json`](../home/.config/nvim/lazy-lock.json) and [`package.toml`](../home/.config/yazi/package.toml), so a fresh machine matches the repository. To move those pins to the latest upstream versions, run:

```sh
zsh setup.sh --skip-system-defaults --update
```

The summary then lists the changed lock files; commit that bump.

Setup stops on a conflicting existing file instead of adopting it; move or merge the reported path, then rerun. A plain `~/.zprofile` that differs from the managed one is moved to `~/.zprofile.local`; if `~/.zprofile.local` already exists, setup refuses until you merge the two.

## What setup does

1. Preflight before changing anything: Stow conflicts, `~/.zprofile`, the tmux plugin manifest, modified or foreign checkouts of nvm, zinit, Homebrew taps and tmux plugins, and strict validation of a running AeroSpace's configuration (a stopped AeroSpace is validated right after launch).
2. Apply macOS defaults and NVRAM settings, unless `--skip-system-defaults` is given.
3. Install Homebrew if missing, tap the [Brewfile](../Brewfile)'s third-party taps and `brew trust` its tap-qualified entries, then install or upgrade the bundle, including its VS Code extensions. A VS Code or Mos app that Homebrew did not install is kept, and the Mos cask is installed on a Mac Studio only (`check.sh --live` applies the same rule).
4. Link `home/` with Stow without adopting existing files, and create `~/.gitconfig` empty if it is missing.
5. Install or update Claude Code and Codex CLI (official installers, `~/.local/bin`), nvm and the latest Node (global packages carried over from the previous default), zinit and the zsh plugins, kitty, SbarLua and the SketchyBar helpers (`~/.local/libexec/sketchybar`), and the tmux plugins; zsh and tmux plugins that are no longer declared are removed.
6. Install the pinned Yazi flavor and Neovim plugins, then install and update Tree-sitter parsers and check the required parsers' highlight queries.
7. Restart OpenUsage, load the configuration in [`home/.config/lockime/rules.json`](../home/.config/lockime/rules.json) into LockIME and launch or relaunch it, reload AeroSpace's config in place (launching or relaunching it only when it is not running or its binary changed), then restart SketchyBar once AeroSpace responds, and check that each service responds.

Setup fails when a Neovim plugin task fails, a zinit update logs an error or leaves a plugin behind its upstream (log: `${XDG_STATE_HOME:-~/.local/state}/dotfiles/zinit-update.log`), or a required Tree-sitter parser fails to install or lacks its highlight query.

## Configuration layout

| Location                                                                                          | Purpose                                                                                               |
| ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| [`home/`](../home/)                                                                               | GNU Stow package deployed into the home directory                                                     |
| [`home/.config/`](../home/.config/)                                                               | Application settings and runtime scripts                                                              |
| [`home/bin/`](../home/bin/)                                                                       | Command helpers                                                                                       |
| [`home/Library/LaunchAgents/`](../home/Library/LaunchAgents/)                                     | Managed LaunchAgents                                                                                  |
| [`home/Library/Application Support/Code/User/`](../home/Library/Application%20Support/Code/User/) | VS Code settings and keybindings                                                                      |
| [`setup.sh`](../setup.sh), [`check.sh`](../check.sh), [`lib/`](../lib/), [`tests/`](../tests/)    | Installation, validation, shared logic, and check fixtures                                            |
| [`patches/aerospace/`](../patches/aerospace/)                                                     | Source patch applied by `lib/build_aerospace_patch.zsh`; see [aerospace-patch.md](aerospace-patch.md) |
| [`stow-target-dirs.txt`](../stow-target-dirs.txt)                                                 | Directories that must stay real instead of becoming directory symlinks                                |

Put machine-specific login-shell additions in untracked `~/.zprofile.local`, which loads after the managed login profile. Generated files are excluded through [`.gitignore`](../.gitignore) and [`home/.stow-local-ignore`](../home/.stow-local-ignore).

Git settings are tracked in [`home/.config/git/config`](../home/.config/git/config). Git reads `~/.gitconfig` after that file, and `git config --global` and `gh auth setup-git` write to `~/.gitconfig` while it exists, so setup keeps it present, empty and untracked: machine-local settings override the tracked ones without dirtying the repository.

### Agent instructions

Setup links [`home/.codex/AGENTS.md`](../home/.codex/AGENTS.md) into a real `~/.codex`, and [`home/.claude/CLAUDE.md`](../home/.claude/CLAUDE.md) and [`home/.claude/settings.json`](../home/.claude/settings.json) into a real `~/.claude`. Other files in those directories stay machine-local. Start a new Codex or Claude Code session after editing them.

## Validate changes

`zsh check.sh` runs syntax and manifest checks, the fixtures in `check.sh` and `tests/`, strict C builds with static analysis, and isolated Stow simulations; it never installs or updates tools. `zsh check.sh --live` adds read-only checks of installed fonts, Neovim parsers and queries, AeroSpace, an isolated tmux server, and the Homebrew bundle, and lists undeclared Brew dependencies without removing them. If that listing cannot finish, the run ends with `Required checks passed with warnings` instead of failing.

## Troubleshooting

- **LockIME did not start on a first run:** approve the macOS prompt for the newly downloaded app, then rerun setup.
- **AeroSpace or SketchyBar does not start:** read the postflight output, then run `zsh check.sh --live`.
- **Desktop flashes during AeroSpace workspace switches:** see the [AeroSpace patch](aerospace-patch.md).
