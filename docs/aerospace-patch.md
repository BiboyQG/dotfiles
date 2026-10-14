# AeroSpace workspace transition patch

The official `v0.21.3-Beta` release (`d56e1637c3a1ed660d0cadd7534e94fb3218d1c3`)
can expose the desktop while switching workspaces: requests to restore incoming
windows and hide outgoing windows run on different application threads, and the
outgoing application can finish first. The upstream tracking issue is
[#1305](https://github.com/nikitabobko/AeroSpace/issues/1305).

The local [source patch](../patches/aerospace/workspace-transition.patch) waits
for incoming frame operations before hiding outgoing windows. It also invalidates
superseded transitions so that rapid switching cannot finish an older hide or
focus operation after a newer transition.

## Build

Requires Apple Silicon, full Xcode with Swift 6.2 or newer, Homebrew Bash 5
(`brew install bash`), Git, and network access for the pinned upstream source
and Swift packages:

```sh
zsh lib/build_aerospace_patch.zsh
```

The script verifies the upstream commit, applies the patch, runs the upstream
Swift tests including the regression tests in the patch, and builds a Release
App and matching CLI. Each run uses a fresh directory under
`~/Library/Caches/dotfiles/aerospace/`; an optional argument selects another
build parent directory. It prints the artifact directory and retains test and
build logs. It does not install or start an application.

Both binaries include a `workspace-fix.<hash>` version suffix, where `<hash>` is
the first 12 hex digits of the patch's SHA-256. `build-info.txt` records the
upstream commit, full patch hash, and compiler versions. The artifacts use local
ad-hoc signing. Warnings that newer toolchains raise for unchanged upstream code
stay in the logs and do not fail the build.

## Local installation and rollback

Back up the current App, the target of `/opt/homebrew/bin/aerospace`, each
window's ID and workspace, and the focused window. Quit AeroSpace, copy the built
App to `/Applications/AeroSpace.app` (it keeps the upstream bundle ID), copy the
CLI to `~/.local/libexec/aerospace/workspace-fix.<hash>/aerospace`, and repoint
`/opt/homebrew/bin/aerospace` to it. Only one AeroSpace instance should manage
windows at a time. Pin the cask so `brew bundle` does not replace it:

```sh
brew pin --cask aerospace
```

A restart drops AeroSpace's workspace tree: move each window back with
`aerospace move-node-to-workspace --window-id ID WORKSPACE`, reset each
workspace's layout (for example `aerospace layout --workspace 1 --root h_tiles`),
then restore focus. Nested splits are not reconstructed. After the signing
identity changes, macOS may require turning AeroSpace's Accessibility permission
off and on; the server is ready once the CLI responds.

To roll back, quit AeroSpace, restore the backed-up App and CLI link, run
`brew unpin --cask aerospace`, reopen the App (re-enable Accessibility if macOS
asks), restore workspace assignments, and check that `aerospace --version`
reports matching client and server versions. Before upgrading, check whether the
official release fixes #1305.

## Limits

A successful AX operation is not a presentation fence: an unresponsive
application can still delay a switch. After a rebuild, check switches between
applications with different response times and rapid repeated switches.
Switching to an empty workspace intentionally shows the desktop.
