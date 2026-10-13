# Setup and maintenance

[English README](../README.md) · [中文 README](../README.zh-CN.md)

## Install or update

This setup targets Apple Silicon Macs. Install the Xcode Command Line Tools first; setup exits when they are missing:

```sh
xcode-select --install
```

From the repository root, run:

```sh
zsh setup.sh --skip-system-defaults
```

This installs or updates tools, deploys links, and restarts managed services. It skips macOS defaults and NVRAM changes. Run `zsh setup.sh` to include those system preferences.

Setup can still ask for an administrator password with `--skip-system-defaults`: once when Homebrew is not installed yet, once when a full Xcode installation has a license left to accept, and whenever `brew bundle` installs or upgrades a pkg-based cask (SF Symbols, SF Mono, SF Pro).

Neovim plugins and the Yazi flavor are installed at the revisions pinned in [`lazy-lock.json`](../home/.config/nvim/lazy-lock.json) and [`package.toml`](../home/.config/yazi/package.toml), so a fresh machine matches the repository. To move those pins to the latest upstream versions, run:

```sh
zsh setup.sh --skip-system-defaults --update
```

The summary then lists the changed lock files; commit that bump.

Review conflicting existing files before replacing them; the installer does not adopt them into the repository. An existing plain `~/.zprofile` is preserved as `~/.zprofile.local` when needed. If both files already contain local changes, merge them before setup.

## What setup does

- Check Stow, tmux plugin, existing Brew tap, and any running AeroSpace configuration conflicts before changing system settings or installing anything; a stopped AeroSpace instance is validated immediately after launch
- Symlink the dotfiles without adopting existing files, then create an empty untracked `~/.gitconfig` so `git config --global` writes stay out of the repository
- Preserve an existing untracked `.zprofile` as `.zprofile.local` before linking the managed login profile
- Install or upgrade the Homebrew bundle and validate trusted taps
- Keep existing unmanaged Arc and VS Code apps instead of requiring Homebrew to adopt them
- Install the latest kitty release with the official installer, skipping the download when the installed app already reports the current version
- Install [Claude Code](https://code.claude.com/docs/en/setup) and [Codex CLI](https://learn.chatgpt.com/docs/codex/cli) with their official native installers into `~/.local/bin`, independently of npm and Homebrew; an installed Claude Code updates itself with `claude update` instead of downloading the installer again
- Install or update nvm, Node, zinit, SbarLua, and tmux plugins to their latest upstream versions, removing tmux plugin checkouts that `plugins.conf` no longer declares; when Node moves to a new release, its global packages are reinstalled from the previous default, which is then removed
- Install the Yazi flavor and Neovim plugins at the revisions pinned in `package.toml` and `lazy-lock.json`; `--update` moves both to the latest upstream versions and lists the lock changes to commit
- Install declared VS Code extensions and pre-install zsh plugins
- Verify Neovim plugin installation, update, build, and cleanup tasks; fail setup if any task fails
- Verify zinit update diagnostics and plugin revisions, retaining the log in `~/.local/state/dotfiles/zinit-update.log` (or `$XDG_STATE_HOME/dotfiles/`)
- Wait for Neovim Tree-sitter parser updates and validate their highlight queries before finishing the editor setup
- Deploy VS Code settings and keybindings into `~/Library/Application Support/Code/User` through the Stow package
- Deploy shared Codex instructions from `home/.codex/AGENTS.md` to `~/.codex/AGENTS.md`; keep other Codex configuration and runtime state machine-local
- Build SketchyBar helpers into `~/.local/libexec/sketchybar`, then restart OpenUsage and AeroSpace, wait for AeroSpace to become ready, and restart SketchyBar with postflight checks


## Configuration layout

| Location | Purpose |
| --- | --- |
| [`home/`](../home/) | GNU Stow package deployed into the home directory |
| [`home/.config/`](../home/.config/) | Application settings and runtime scripts |
| [`home/bin/`](../home/bin/) | Command helpers |
| [`home/Library/LaunchAgents/`](../home/Library/LaunchAgents/) | Managed LaunchAgents |
| [`home/Library/Application Support/Code/User/`](../home/Library/Application%20Support/Code/User/) | VS Code settings and keybindings |
| [`setup.sh`](../setup.sh), [`check.sh`](../check.sh), [`lib/`](../lib/) | Installation, validation, and shared logic |
| [`stow-target-dirs.txt`](../stow-target-dirs.txt) | Directories that must stay real instead of becoming directory symlinks |

Powerlevel10k settings, Neovim's plugin lock, and Yazi's package manifest are tracked in [`home/.p10k.zsh`](../home/.p10k.zsh), [`lazy-lock.json`](../home/.config/nvim/lazy-lock.json), and [`package.toml`](../home/.config/yazi/package.toml).

Put machine-specific login-shell additions in untracked `~/.zprofile.local`, which loads after the managed login profile. Generated files are excluded through [`.gitignore`](../.gitignore) and [`home/.stow-local-ignore`](../home/.stow-local-ignore).

Git settings are tracked in [`home/.config/git/config`](../home/.config/git/config), which Git reads before `~/.gitconfig`. Setup creates `~/.gitconfig` empty and untracked; `git config --global` and `gh auth setup-git` write there while the file exists, so machine-local Git settings override the tracked ones and never dirty the repository.

### Codex global instructions

Edit [`home/.codex/AGENTS.md`](../home/.codex/AGENTS.md) to change shared working preferences. Setup links only that file into the real `~/.codex` directory; other Codex files remain local.

Codex discovers instructions when a run starts. Start a new session after editing the file. A local `~/.codex/AGENTS.override.md` takes precedence; a custom `CODEX_HOME` changes the directory Codex reads. See the [official instruction discovery guide](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

## Validate changes

```sh
zsh check.sh
zsh check.sh --live
```

The default suite runs syntax and manifest checks, deterministic runtime fixtures, strict C compilation and static analysis, and isolated Stow simulations. It covers setup preflight, tmux routing and restore coordination, clipboard content, SketchyBar, shell completion, NVM, zinit, Neovim plugin sync, and Tree-sitter failure handling without installing or updating tools.

Live mode adds read-only checks of installed fonts, Neovim parsers and queries, AeroSpace, an isolated tmux server, and the Homebrew bundle. The optional Brew cleanup audit reports undeclared dependencies without removing them. If that audit cannot finish, the final summary says `Required checks passed with warnings` and identifies the incomplete audit; mandatory checks still fail with a nonzero exit status.

## Useful diagnostics

- **Setup stops at a file conflict:** inspect the reported path and move or merge the conflicting local file before rerunning setup.
- **A zinit update fails:** inspect `~/.local/state/dotfiles/zinit-update.log`, or `$XDG_STATE_HOME/dotfiles/zinit-update.log` if configured. Setup checks diagnostics and plugin revisions before accepting an update.
- **Neovim parser setup fails:** setup waits for Tree-sitter updates and validates highlight queries; inspect the reported parser or query error and rerun setup after resolving it.
- **AeroSpace or SketchyBar fails to start:** inspect setup's service postflight output; use `zsh check.sh --live` to check the current configuration.
- **Desktop flashes during AeroSpace workspace switches:** see the [local AeroSpace patch](aerospace-patch.md) for the pinned upstream version, rebuild instructions, and rollback procedure.
