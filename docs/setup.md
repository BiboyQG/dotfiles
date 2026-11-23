# Setup and maintenance

[English README](../README.md) · [中文 README](../README.zh-CN.md)

## Install or update

Run the commands in the [README quick start](../README.md#quick-start); to update an existing clone, run `git pull` and then `zsh setup.sh --skip-system-defaults` in it. Setup exits when the Xcode Command Line Tools are missing.

With `--skip-system-defaults`, setup asks for an administrator password only to install Homebrew, accept a pending Xcode license, or install or upgrade the pkg-based casks (SF Symbols, SF Mono, SF Pro). Run `zsh setup.sh` without the flag once on each Mac: its defaults step turns off the input-source indicator, which otherwise stalls AeroSpace on every switch LockIME makes.

The Yazi flavor is installed at the revision pinned in [`package.toml`](../home/.config/yazi/package.toml), so a fresh machine matches the repository. To move that pin to the latest upstream version, run:

```sh
zsh setup.sh --skip-system-defaults --update
```

The summary then lists the changed lock file; commit that bump.

Setup stops on a conflicting existing file instead of adopting it; move or merge the reported path, then rerun. A plain `~/.zprofile` that differs from the managed one is moved to `~/.zprofile.local`; if `~/.zprofile.local` already exists, setup refuses until you merge the two.

## What setup does

1. Preflight before changing anything: Stow conflicts, `~/.zprofile`, the tmux plugin manifest, modified or foreign checkouts of zinit, Homebrew taps and tmux plugins, and strict validation of a running AeroSpace's configuration (a stopped AeroSpace is validated right after launch).
2. Apply macOS defaults and NVRAM settings, unless `--skip-system-defaults` is given.
3. Install Homebrew if missing, tap the [Brewfile](../Brewfile)'s third-party taps and `brew trust` its tap-qualified entries, then install or upgrade the bundle. A Zed or Mos app that Homebrew did not install is kept, and the Mos cask is installed on a Mac Studio only (`check.sh --live` applies the same rule).
4. Link `home/` with Stow without adopting existing files, and create `~/.gitconfig` empty if it is missing.
5. Install or update Claude Code, Codex CLI, and Antigravity CLI (official installers, `~/.local/bin`), zinit and the zsh plugins, kitty, the `zed` CLI link (`~/.local/bin/zed`), SbarLua and the SketchyBar menu helper (`~/.local/libexec/sketchybar`), the tmux plugins, and the pinned Yazi flavor; zsh and tmux plugins that are no longer declared are removed.
6. Restart OpenUsage, load the configuration in [`home/.config/lockime/rules.json`](../home/.config/lockime/rules.json) into LockIME and launch or relaunch it, reload AeroSpace's config in place (launching or relaunching it only when it is not running or its binary changed), then restart SketchyBar once AeroSpace responds, and check that each service responds.

Setup fails when a zinit update logs an error or leaves a plugin behind its upstream (log: `${XDG_STATE_HOME:-~/.local/state}/dotfiles/zinit-update.log`).

## Configuration layout

| Location                                                                                       | Purpose                                                                |
| ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| [`home/`](../home/)                                                                            | GNU Stow package deployed into the home directory                      |
| [`home/.config/`](../home/.config/)                                                            | Application settings and runtime scripts                               |
| [`home/bin/`](../home/bin/)                                                                    | Command helpers                                                        |
| [`home/Library/LaunchAgents/`](../home/Library/LaunchAgents/)                                  | Managed LaunchAgents                                                   |
| [`setup.sh`](../setup.sh), [`check.sh`](../check.sh), [`lib/`](../lib/), [`tests/`](../tests/) | Installation, validation, shared logic, and check fixtures             |
| [`stow-target-dirs.txt`](../stow-target-dirs.txt)                                              | Directories that must stay real instead of becoming directory symlinks |

Put machine-specific login-shell additions in untracked `~/.zprofile.local`, which loads after the managed login profile. Generated files are excluded through [`.gitignore`](../.gitignore) and [`home/.stow-local-ignore`](../home/.stow-local-ignore).

Git settings are tracked in [`home/.config/git/config`](../home/.config/git/config). Git reads `~/.gitconfig` after that file, and `git config --global` and `gh auth setup-git` write to `~/.gitconfig` while it exists, so setup keeps it present, empty and untracked: machine-local settings override the tracked ones without dirtying the repository.

### Agent instructions

Setup links [`home/.codex/AGENTS.md`](../home/.codex/AGENTS.md) into a real `~/.codex`, and [`home/.claude/CLAUDE.md`](../home/.claude/CLAUDE.md) and [`home/.claude/settings.json`](../home/.claude/settings.json) into a real `~/.claude`, and each skill in [`home/.claude/skills/`](../home/.claude/skills/) into a real `~/.claude/skills`. Other files in those directories stay machine-local. Start a new Codex or Claude Code session after editing them.

## Validate changes

`zsh check.sh` runs syntax and manifest checks, the fixtures in `check.sh` and `tests/`, strict C builds with static analysis, and isolated Stow simulations; it never installs or updates tools. `zsh check.sh --live` adds read-only checks of installed fonts, AeroSpace, an isolated tmux server, and the Homebrew bundle, and lists undeclared Brew dependencies without removing them. If that listing cannot finish, the run ends with `Required checks passed with warnings` instead of failing.

## Troubleshooting

- **LockIME did not start on a first run:** approve the macOS prompt for the newly downloaded app, then rerun setup.
- **AeroSpace or SketchyBar does not start:** read the postflight output, then run `zsh check.sh --live`.
