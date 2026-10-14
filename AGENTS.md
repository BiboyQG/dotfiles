# Repository Guidelines

## Project Structure & Module Organization

This repository manages dotfiles for an Apple Silicon Mac; Intel Macs are not supported. Deployable files live in the `home/` GNU Stow package; the per-directory layout is in `docs/setup.md`. Repository tooling stays at the root: `setup.sh` installs and links the environment, `check.sh` validates it, `Brewfile` declares packages, `stow-target-dirs.txt` lists the deployed directories that must stay real directories, and `lib/` holds the zsh and Neovim Lua helpers that `setup.sh` runs plus the build script for the AeroSpace patch in `patches/aerospace/`. User documentation is in `docs/`.

## Build, Test, and Development Commands

- `zsh check.sh` runs the standard non-destructive suite: syntax checks, fixtures, strict C compilation, manifest validation, and isolated Stow simulations.
- `zsh check.sh --live` adds read-only checks against installed fonts, Neovim, AeroSpace, tmux, and Homebrew. Run it for machine-integrated changes.
- `zsh setup.sh --skip-system-defaults` installs or updates dependencies, deploys links, and restarts or reloads OpenUsage, AeroSpace, and SketchyBar, without changing macOS defaults or NVRAM.
- `zsh setup.sh` additionally applies macOS defaults and NVRAM preferences (asks for sudo up front).
- Add `--update` to either command to move `home/.config/nvim/lazy-lock.json` and `home/.config/yazi/package.toml` to the latest upstream versions; commit the lock changes it lists.

## Coding Style & Naming Conventions

Preserve the style of the file being edited. Shell code uses zsh or bash explicitly, `set -euo pipefail`, two-space indentation, `snake_case` functions and locals, and uppercase global constants. Lua also uses two-space indentation and local `snake_case` helpers. Python uses four-space indentation and the standard library only. Keep TOML, JSON, plist, and application configs minimal; prefer existing mechanisms over new utilities. Remove debug output, dead code, and temporary scaffolding.

## Testing Guidelines

Add deterministic fixtures to `check.sh` or a focused `tests/*_spec.lua` or `tests/*_spec.py` file that takes the repository root as its first argument; add a Python spec to `RUNTIME_SPECS` in `check.sh` by its name without `_spec.py` (those specs run in parallel, so each must use its own temp directory and sockets) and a Lua spec as its own `lua tests/<name>_spec.lua "$ROOT"` line. Mock external services instead of depending on network state. Run `zsh check.sh` for every change and `zsh check.sh --live` when runtime integration is affected. Also run `git diff --check` before committing.

## Commit & Pull Request Guidelines

Follow the established Conventional Commit style, such as `fix(yazi): restore zoxide directory jump` or `refactor(check): build the SketchyBar helpers with the shared flags`. Keep commits scoped to one concern and stage exact paths; never sweep unrelated working-tree changes into a commit. Pull requests should explain the problem, user-visible impact, validation performed, and any macOS-specific assumptions. Include screenshots for visual SketchyBar changes and link relevant issues when available.

## Security & Local Configuration

Do not commit secrets, tokens, generated application state, or machine-local Codex or Claude Code data. Put login-shell overrides in untracked `~/.zprofile.local` and machine-local Git settings in untracked `~/.gitconfig` (the tracked config is `home/.config/git/config`). Update `home/.stow-local-ignore` when a new generated path must remain undeployed, and `stow-target-dirs.txt` when a new deployed directory must stay a real directory.
