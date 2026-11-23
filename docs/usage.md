# Everyday usage

[English README](../README.md) · [中文 README](../README.zh-CN.md)

## AeroSpace

- `Alt+1..0` switch to workspace 1..10; `Alt+Shift+1..0` move the window there and follow it
- `Alt+h/j/k/l` focus, `Alt+Shift+h/j/k/l` move, `Ctrl+Alt+h/j/k/l` grow the window toward that side, or shrink it when no window is there
- `Cmd+Enter` opens kitty, `Cmd+Shift+Enter` a new Phi window
- `Alt+f` fullscreen, `Alt+z` toggle floating, `Alt+q` close, `Ctrl+Alt+Shift+r` reload the config

The full list is in [`aerospace.toml`](../home/.config/aerospace/aerospace.toml).

## tmux

Keys bound without the prefix (tmux's root table), active in every pane:

- `Ctrl+f` toggles pane zoom, `Ctrl+o` opens a window in the current pane's
  directory, `Ctrl+q` kills the current window, and `Ctrl+v` enters copy mode
  (`v` selects, `y` copies to the clipboard)
- `Ctrl+1..9` select window 1..9 (kitty sends them as CSI u so tmux can tell
  them apart from plain digits)
- `F11` (kitty `⌘N`) moves to the next window and `Shift+F11` (kitty `⌘D`) detaches the client

Prefix bindings: `|` and `-` split the pane (`h`/`j`/`k`/`l` split toward that
side) and `r` reloads the configuration.

## Zsh

`Ctrl+p`/`Ctrl+n` search history for lines starting with the current first word, `Ctrl+x Ctrl+e` edits the command line in `$EDITOR` (`zed --wait`), and `Ctrl+x g c` inserts `git commit -m ""` with the cursor between the quotes. Flow control is off (`stty -ixon`), so `Ctrl+s` and `Ctrl+q` do not freeze the terminal.

## Zed

Zed ([keymap](../home/.config/zed/keymap.json)): `Ctrl+h/j/k/l` move focus spatially across the Threads Sidebar, left Agent / Terminal Thread panel, center editor, right Project Panel, and bottom terminal (`Ctrl+j` and `Ctrl+w` stay with the CLI inside an Agent Terminal Thread); `Ctrl+Shift+h/j/k/l` toggle the left, bottom, Threads Sidebar, and right docks, and `Ctrl+Shift+f` toggles all docks; `Ctrl+[` / `Ctrl+]` switch the previous / next editor tab, terminal tab, or thread; `Ctrl+w` closes the focused bottom terminal; `Space Space` opens the file finder in Vim Normal mode; in the Project Panel, `a`/`A`, `r`, `c`, `x`, `p`, `d`, `s`/`S` create, rename, copy, cut, paste, delete, and split, and in the Threads Sidebar, `t`, `a`, `r`, `d` open a Terminal Thread, create, rename, and archive threads.

## Input sources

LockIME switches the input source when an app activates. The per-app rules are in [`rules.json`](../home/.config/lockime/rules.json); setup loads that file into LockIME on every run, replacing everything set in LockIME's own window except the menu-bar icon setting.

## Shell shortcuts

Defined in [`home/.zshrc`](../home/.zshrc) and [`home/bin/`](../home/bin/):

| Command      | Runs                                                   |
| ------------ | ------------------------------------------------------ |
| `ll`         | `eza -alh` listing with icons                          |
| `s`          | `fastfetch`                                            |
| `l`          | `lazygit`                                              |
| `y`          | `yazi`, then `cd` to the directory it exits in         |
| `c`          | `claude`                                               |
| `codex`      | `codex --dangerously-bypass-approvals-and-sandbox`     |
| `cat`        | `bat`                                                  |
| `tn <name>`  | `tmux new -s <name>`                                   |
| `ta`         | `tmux attach`                                          |
| `tls`        | `tmux ls`                                              |
| `abs <path>` | print the absolute path and copy it to the clipboard   |
| `ip`         | print the public IPv4 address                          |
