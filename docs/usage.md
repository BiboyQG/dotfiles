# Everyday usage

[English README](../README.md) · [中文 README](../README.zh-CN.md)

## tmux

Some tmux behavior in this repo is optimized for “session slots” (fast switching / moving windows):

- Sessions are auto-renamed to `<index>-<label>` (example: `1-dot`, `2-spreadsheet-build`)
- Rename the current session label with `<prefix> + .` (the prompt omits the numeric prefix)
- New sessions (`tn <label>`, or tmux's own `new-session`) are numbered automatically by the session-created hook
- Switch sessions with `F1..F10` (in Kitty, `⌘1..⌘0` sends `F1..F10` to tmux)
- Move the current window to session slot with `<prefix> + 1..0`
- Automatic startup restore keeps saved session names until tmux-resurrect has
  restored windows and removed its initial placeholder, then numbers sessions
  once. The startup wrapper retains Continuum's multiple-server check and
  `~/tmux_no_auto_restore` opt-out; Continuum continues to save automatically.

Keys bound without the prefix (tmux's root table), active in every pane:

- `Ctrl+f` toggles pane zoom, `Ctrl+o` opens a window in the current pane's
  directory, `Ctrl+q` kills the current window, and `Ctrl+v` enters copy mode
  (`v` selects, `y` copies to the clipboard)
- `Ctrl+1..9` select window 1..9 (kitty sends them as CSI u so tmux can tell
  them apart from plain digits)
- `F11` moves to the next window and `Shift+F11` detaches the client
- `Ctrl+h/j/k/l` move between panes and Neovim splits (vim-tmux-navigator)

Only the `Ctrl+h/j/k/l` bindings pass the key on when Neovim has focus. Inside
tmux, Neovim therefore never receives `Ctrl+f` (page forward), `Ctrl+o` (jump
back) or `Ctrl+v` (visual block), and readline never receives `Ctrl+o` or
`Ctrl+q`.

Prefix bindings: `|` and `-` split the pane (`h`, `j`, `k`, `l` split toward
that side), `r` reloads the configuration, `.` renames the session label, and
`1..0` move the current window to a session slot.

Shell helpers:

- `ta <label>` attaches by label (example: `ta dot` attaches to `1-dot`);
  inside tmux it switches the client instead
- `ta <idx>` attaches by slot (example: `ta 1`)
- `tls` lists sessions

## Zsh

XON/XOFF flow control is disabled in interactive shells (`stty -ixon`), so `Ctrl+s` and `Ctrl+q` never freeze the terminal.

## Editors

- VS Code: `Ctrl+]` and `Ctrl+Shift+[` open the next and previous editor while the text editor has focus. `Ctrl+[` retains Vim's Escape behavior and passes through to the terminal.
- Neovim: Neo-tree shows dotfiles and hides Git-ignored files by default. Toggle hidden items in Neo-tree when you need to inspect ignored files.
- Yazi: PDF files open with the default macOS application.

## Shell shortcuts

Aliases and helper functions are defined in [`home/.zshrc`](../home/.zshrc):

| Alias | Command                              | Description                                  |
| ----- | ------------------------------------ | -------------------------------------------- |
| ll    | eza -alh --icons=auto --color=always | Enhanced file listing with icons and details |
| s     | fastfetch                            | System information display                   |
| l     | lazygit                              | Terminal Git UI                              |
| y     | yazi function                        | File manager with directory changing support |
| c     | claude                               | Claude Code CLI                              |
| tn    | tmux new -s                          | Create a new tmux session                    |
| ta    | ta <label\|idx>                      | Attach to a tmux session                     |
| cat   | bat                                  | Syntax-highlighted file output               |
