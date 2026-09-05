# Everyday usage

[English README](../README.md) · [中文 README](../README.zh-CN.md)

## tmux

Some tmux behavior in this repo is optimized for “session slots” (fast switching / moving windows):

- Sessions are auto-renamed to `<index>-<label>` (example: `1-dot`, `2-spreadsheet-build`)
- Rename the current session label with `<prefix> + .` (the prompt omits the numeric prefix)
- Create a new session with `Ctrl+s` (keeps numbering contiguous)
- Switch sessions with `F1..F10` (in Kitty, `⌘1..⌘0` sends `F1..F10` to tmux)
- Move the current window to session slot with `<prefix> + 1..0`

Shell helpers:

- `ta <label>` attaches by label (example: `ta dot` attaches to `1-dot`)
- `ta <idx>` attaches by slot (example: `ta 1`)
- `tls` lists sessions

## Zsh

`Ctrl+s` is bound in tmux, so XON/XOFF is disabled in interactive shells to avoid terminal “freezing”.

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
