# Everyday usage

[English README](../README.md) · [中文 README](../README.zh-CN.md)

## AeroSpace

- `Alt+1..0` switch to workspace 1..10; `Alt+Shift+1..0` move the window there and follow it
- `Alt+h/j/k/l` focus, `Alt+Shift+h/j/k/l` move, `Ctrl+Alt+h/j/k/l` grow the window toward that side, or shrink it when no window is there
- `Cmd+Enter` opens kitty, `Cmd+Shift+Enter` a new Arc window
- `Alt+f` fullscreen, `Alt+z` toggle floating, `Alt+q` close, `Ctrl+Alt+Shift+r` reload the config

The full list is in [`aerospace.toml`](../home/.config/aerospace/aerospace.toml).

## tmux

Sessions occupy numbered slots named `<slot>-<label>` (for example `1-dot`) and are renumbered automatically when a session is created or closed, including ones created with `tn <label>`.

- `F1..F10` switch to slot 1..10 (in kitty, `⌘1..⌘0` send `F1..F10`)
- `<prefix> + 1..0` moves the current window to session slot 1..10 and switches to that slot
- `<prefix> + .` renames the current session's label
- When the tmux server starts, tmux-resurrect restores the last saved sessions and they are then renumbered. Continuum saves automatically. The restore is skipped when another tmux server is running or `~/tmux_no_auto_restore` exists.

Keys bound without the prefix (tmux's root table), active in every pane:

- `Ctrl+f` toggles pane zoom, `Ctrl+o` opens a window in the current pane's
  directory, `Ctrl+q` kills the current window, and `Ctrl+v` enters copy mode
  (`v` selects, `y` copies to the clipboard)
- `Ctrl+1..9` select window 1..9 (kitty sends them as CSI u so tmux can tell
  them apart from plain digits)
- `F11` (kitty `⌘N`) moves to the next window and `Shift+F11` (kitty `⌘D`) detaches the client
- `Ctrl+h/j/k/l` move between panes and Neovim splits, and `Ctrl+\` returns to the previous one (vim-tmux-navigator)

Apart from `Ctrl+h/j/k/l` and `Ctrl+\`, which pass through when the pane is
running Vim, Neovim or fzf, these keys never reach the program in the pane.

Prefix bindings: `|` and `-` split the pane (`h`/`j`/`k`/`l` split toward that
side) and `r` reloads the configuration.

## Zsh

`Ctrl+p`/`Ctrl+n` search history for lines starting with the current first word, `Ctrl+x Ctrl+e` edits the command line in `$EDITOR`, and `Ctrl+x g c` inserts `git commit -m ""` with the cursor between the quotes. Flow control is off (`stty -ixon`), so `Ctrl+s` and `Ctrl+q` do not freeze the terminal.

## Editors

- VS Code ([keybindings](../home/Library/Application%20Support/Code/User/keybindings.json)): `Ctrl+h` moves focus between the sidebar and the editor, `Ctrl+l` from the sidebar to the editor, and `Ctrl+j`/`Ctrl+k` to the terminal (inside the terminal, `Ctrl+h/j/k` go to the shell); `⇧⌘N` opens a terminal and `Ctrl+w` closes the focused one; `Space Space` opens Quick Open in Vim Normal mode; `Ctrl+]` / `Ctrl+Shift+[` open the next / previous editor; in the Explorer, `a`, `r`, `c`, `x`, `p`, `d`, `s` create, rename, copy, cut, paste, delete and open to the side.
- Neovim: Neo-tree shows dotfiles; Git-ignored files stay hidden until you press `H`.

## Shell shortcuts

Defined in [`home/.zshrc`](../home/.zshrc) and [`home/bin/`](../home/bin/):

| Command            | Runs                                                                        |
| ------------------ | --------------------------------------------------------------------------- |
| `ll`               | `eza -alh` listing with icons                                               |
| `s`                | `fastfetch`                                                                 |
| `l`                | `lazygit`                                                                   |
| `y`                | `yazi`, then `cd` to the directory it exits in                              |
| `c`                | `claude`                                                                    |
| `codex`            | `codex --dangerously-bypass-approvals-and-sandbox`                          |
| `cat`              | `bat`                                                                       |
| `tn <label>`       | new tmux session (numbered automatically)                                   |
| `ta <label\|slot>` | attach by label or slot (`ta dot`, `ta 1`); switches the client inside tmux |
| `tls`              | `tmux ls`                                                                   |
| `abs <path>`       | print the absolute path and copy it to the clipboard                        |
| `ip`               | print the public IPv4 address                                               |
