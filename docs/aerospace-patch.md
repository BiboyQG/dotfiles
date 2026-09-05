# AeroSpace workspace transition patch

The official `v0.21.3-Beta` release (`d56e1637c3a1ed660d0cadd7534e94fb3218d1c3`)
can expose the desktop while switching workspaces: requests to restore incoming
windows and hide outgoing windows run on different application threads, and the
outgoing application can finish first. The upstream tracking issue is
[#1305](https://github.com/nikitabobko/AeroSpace/issues/1305).

The local [source patch](../patches/aerospace/workspace-transition.patch) waits
for incoming frame operations before hiding outgoing windows. It also invalidates
superseded transitions so that rapid switching cannot finish an older hide or
focus operation after a newer transition. It does not add an arbitrary delay or
change AeroSpace keybindings.

## Build

Requires Apple Silicon, full Xcode with Swift 6.2 or newer, Homebrew Bash 5, Git,
and network access for the pinned upstream source and Swift packages:

```sh
zsh lib/build_aerospace_patch.zsh
```

The script verifies the upstream commit, applies the patch, runs the upstream
Swift tests including the regression tests in the patch, and builds a Release
App and matching CLI. Each run uses a fresh directory under
`~/Library/Caches/dotfiles/aerospace/`; an optional argument selects another
build parent directory. It prints the artifact directory and retains test and
build logs. It does not install or start an application.

Both binaries include a `workspace-fix` version suffix derived from the patch's
SHA-256. `build-info.txt` records the upstream commit, full patch hash, and
compiler versions. The artifacts use local ad-hoc signing.

Compiler warnings remain in the logs. This local build does not promote Swift
warnings to errors: Xcode 27 / Swift 6.4 diagnoses unnecessary `unsafe`
expressions in unchanged upstream code originally built with Swift 6.3.2.

## Local installation and rollback

The App and CLI must be installed together, after backing up the current App,
CLI symlink target, and the window IDs, workspace assignments, and focused
window. The installed App stays at `/Applications/AeroSpace.app` with the
upstream bundle ID. Only one instance should manage windows at a time.

Quit AeroSpace before replacement. A restart does not preserve AeroSpace's
workspace tree, so restore existing windows to their recorded workspaces with
`aerospace move-node-to-workspace --window-id ID WORKSPACE`. Restore each
workspace's recorded layout as well (for example,
`aerospace layout --workspace 1 --root h_tiles`); the startup layout can otherwise
leave a single remaining window in an accordion container. Then restore focus.
Window assignments alone do not reconstruct a complex nested split tree.
macOS may require turning AeroSpace's Accessibility permission off and
on after its signing identity changes. The server is not ready until that
permission is granted and the CLI can communicate with it.

Pin the installed cask while using the patch:

```sh
brew pin --cask aerospace
```

This also prevents normal `brew bundle` upgrades from replacing the patch.
Before upgrading, check whether the official release fixes #1305. To return to
the official build, quit AeroSpace, restore the backed-up App and CLI link,
then run `brew unpin --cask aerospace` and reopen the App. Restore workspace
assignments and verify `aerospace --version` reports matching client/server
versions. Accessibility permission may need to be granted again.

Keep source patches, tests, and build instructions in Git. Keep App bundles,
compiler caches, local backups, and window-state snapshots outside the repo.

## Validation limits

Regression tests cover request ordering and superseded transitions. A successful
AX operation is not a WindowServer presentation fence: an unresponsive or
misbehaving application can still cause delays. Live checks should include
switches between applications with different response times and rapid repeated
switches. Switching to an empty workspace intentionally shows the desktop.

On the target Mac (macOS 27, one 1920 × 1080 display), a 10-second geometry
sample during the same 12 switches plus return found eight near-zero coverage
intervals (9–64 ms) with the official build, and none with the patch. A separate
16-command rapid-switch run returned successfully and retained the requested
final focus. Geometry sampling is not a recording of displayed frames; its
sampling gaps limit the duration of flickers it can detect.
