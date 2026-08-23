# Repository Guidelines

## Project Structure & Module Organization

This repository manages dotfiles for an Apple Silicon Mac; Intel Macs are not supported. Deployable files live in the `home/` GNU Stow package. Application configuration is under `home/.config/`, shell entry points are in `home/`, command helpers are in `home/bin/`, launch agents are in `home/Library/LaunchAgents/`, and VS Code user settings are in `home/Library/Application Support/Code/User/`. Repository tooling stays at the root: `setup.sh` installs and links the environment, `check.sh` validates it, `Brewfile` declares packages, and `lib/` contains shared shell logic. Deterministic test code belongs in `tests/`, currently including `tests/sketchybar_runtime_spec.lua`.

## Build, Test, and Development Commands

- `zsh check.sh` runs the standard non-destructive suite: syntax checks, fixtures, strict C compilation, manifest validation, and isolated Stow simulations.
- `zsh check.sh --live` adds read-only checks against installed fonts, Neovim, AeroSpace, tmux, and Homebrew. Run it for machine-integrated changes.
- `zsh setup.sh --skip-system-defaults` installs dependencies and deploys links without changing macOS defaults or NVRAM.
- `zsh setup.sh` performs the complete Apple Silicon setup and may restart managed services.

## Coding Style & Naming Conventions

Preserve the style of the file being edited. Shell code uses zsh or bash explicitly, `set -euo pipefail`, two-space indentation, `snake_case` functions and locals, and uppercase global constants. Lua also uses two-space indentation and local `snake_case` helpers. Keep TOML, JSON, plist, and application configs minimal; prefer existing mechanisms over new utilities. Remove debug output, dead code, and temporary scaffolding.

## Testing Guidelines

Add deterministic fixtures to `check.sh` or a focused `tests/*_spec.lua` file. Mock external services instead of depending on network state. Run `zsh check.sh` for every change and `zsh check.sh --live` when runtime integration is affected. Also run `git diff --check` before committing.

## Commit & Pull Request Guidelines

Follow the established Conventional Commit style, such as `fix(yazi): restore zoxide directory jump` or `refactor(dotfiles): harden deployment checks`. Keep commits scoped to one concern and stage exact paths; never sweep unrelated working-tree changes into a commit. Pull requests should explain the problem, user-visible impact, validation performed, and any macOS-specific assumptions. Include screenshots for visual SketchyBar changes and link relevant issues when available.

## Security & Local Configuration

Do not commit secrets, tokens, generated application state, or machine-local Codex data. Put login-shell overrides in untracked `~/.zprofile.local`, and update `home/.stow-local-ignore` when a new generated path must remain undeployed.
