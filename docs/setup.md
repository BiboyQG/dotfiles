# Setup and maintenance

[English README](../README.md) · [中文 README](../README.zh-CN.md)

## Install or update

This setup targets Apple Silicon Macs. From the repository root, run:

```sh
zsh setup.sh --skip-system-defaults
```

This installs or updates tools, deploys links, and restarts managed services. It skips macOS defaults and NVRAM changes. Run `zsh setup.sh` to include those system preferences.

Review conflicting existing files before replacing them; the installer does not adopt them into the repository. An existing plain `~/.zprofile` is preserved as `~/.zprofile.local` when needed. If both files already contain local changes, merge them before setup.

## What setup does

- Check Stow, tmux plugin, existing Brew tap, and any running AeroSpace configuration conflicts before changing system settings or installing anything; a stopped AeroSpace instance is validated immediately after launch
- Symlink the dotfiles without adopting existing files
- Preserve an existing untracked `.zprofile` as `.zprofile.local` before linking the managed login profile
- Install or upgrade the Homebrew bundle and validate trusted taps
- Keep existing unmanaged Arc and VS Code apps instead of requiring Homebrew to adopt them
- Install the latest kitty release with the official installer
- Install or update [Claude Code](https://code.claude.com/docs/en/setup) and [Codex CLI](https://learn.chatgpt.com/docs/codex/cli) with their official native installers into `~/.local/bin`, independently of npm and Homebrew
- Install or update nvm, Node, zinit, SbarLua, the Yazi flavor, and tmux plugins to their latest upstream versions
- Install declared VS Code extensions and pre-install zsh and Neovim plugins
- Verify Neovim plugin installation, update, build, and cleanup tasks; fail setup if any task fails
- Verify zinit update diagnostics and plugin revisions, retaining the log in `~/.local/state/dotfiles/zinit-update.log` (or `$XDG_STATE_HOME/dotfiles/`)
- Wait for Neovim Tree-sitter parser updates and validate their highlight queries before finishing the editor setup
- Deploy VS Code settings and keybindings into `~/Library/Application Support/Code/User` through the Stow package
- Deploy shared Codex instructions from `home/.codex/AGENTS.md` to `~/.codex/AGENTS.md`; keep other Codex configuration and runtime state machine-local
- Build SketchyBar helpers into `~/.local/libexec/sketchybar`, then restart OpenUsage and AeroSpace, wait for AeroSpace to become ready, and restart SketchyBar and skhd with postflight checks


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
