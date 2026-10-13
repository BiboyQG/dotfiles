"""Exercise session routing and clipboard yanks against a disposable tmux server."""
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
MANAGER = ROOT / "home/.config/tmux/scripts/session_manager.py"


with tempfile.TemporaryDirectory(prefix="dotfiles-tmux-spec-") as directory:
    work = Path(directory)
    socket = str(work / "tmux.sock")
    base = ["tmux", "-S", socket]

    def tmux(*args, check=True):
        return subprocess.run(base + list(args), capture_output=True, text=True, check=check).stdout.strip()

    try:
        tmux("-f", "/dev/null", "new-session", "-d", "-s", "1-alpha", "/bin/sleep 120")
        tmux("new-session", "-d", "-s", "2-beta", "/bin/sleep 120")
        tmux("new-session", "-d", "-s", "3-gamma", "/bin/sleep 120")
        source = tmux("new-window", "-t", "1-alpha:", "-P", "-F", "#{window_id}", "/bin/sleep 120")
        env = dict(os.environ, TMUX=f"{socket},{tmux('display-message', '-p', '#{pid}')},0")

        def manager(*args, check=True, extra_env=None):
            return subprocess.run(
                [sys.executable, str(MANAGER), *args], env=dict(env, **(extra_env or {})),
                capture_output=True, text=True, check=check,
            )

        # Only inject command failure/disappearance; all naming happens in tmux.
        rename_bin = work / "rename-bin"
        rename_bin.mkdir()
        rename_log, once = work / "renames.log", work / "injected"
        (rename_bin / "tmux").write_text(f'''#!/usr/bin/env python3
import json, os, subprocess, sys
from pathlib import Path
args = sys.argv[1:]
real_tmux = {shutil.which("tmux")!r}
if args and args[0] == "rename-session":
    with open(os.environ["TMUX_RENAME_LOG"], "a") as stream:
        stream.write(json.dumps(args) + "\\n")
    marker = Path(os.environ["TMUX_TEST_ONCE"])
    target = args[args.index("-t") + 1]
    phase = "temporary" if args[-1].startswith("__dotfiles_") else "final"
    if not marker.exists() and target == os.environ.get("TMUX_TEST_FAIL_TARGET") and phase == os.environ.get("TMUX_TEST_FAIL_PHASE"):
        marker.touch()
        sys.exit("injected rename failure")
    if not marker.exists() and target == os.environ.get("TMUX_TEST_VANISH_ID"):
        marker.touch()
        subprocess.run([real_tmux, "kill-session", "-t", target], check=True)
os.execv(real_tmux, [real_tmux, *args])
''')
        (rename_bin / "tmux").chmod(0o755)
        rename_env = dict(
            PATH=f"{rename_bin}:{env['PATH']}", TMUX_RENAME_LOG=str(rename_log),
            TMUX_TEST_ONCE=str(once),
        )

        before = tmux("list-sessions", "-F", "#{session_id}\t#{session_name}")
        for label in ("tabs\there", "multi\nline", "return\rhere", "escape\x1bhere", "delete\x7fhere"):
            result = manager("rename", label, "--session", "$0", check=False, extra_env=rename_env)
            assert result.returncode != 0 and "control characters" in result.stderr
            assert tmux("list-sessions", "-F", "#{session_id}\t#{session_name}") == before
        assert not rename_log.exists(), "invalid labels attempted a rename"

        for label in ("中文.项目:试验", "literal #{session_name} #tag", "unicode\u2028separator"):
            manager("rename", label, "--session", "$0")
            assert tmux("display-message", "-p", "-t", "$0", "#{session_name}") == f"1-{label}"
            assert f"$0::1-{label}\n" in manager("list").stdout

        # Only sessions whose name changes are renamed: a single rename touches
        # one session (temporary name, then final name) and leaves the rest alone.
        def rename_targets():
            return [json.loads(line)[2] for line in rename_log.read_text().splitlines()]

        rename_log.unlink(missing_ok=True)
        manager("rename", "alpha", "--session", "$0", extra_env=rename_env)
        assert rename_targets() == ["$0", "$0"], rename_targets()
        assert tmux("list-sessions", "-F", "#{session_id}\t#{session_name}") == "$0\t1-alpha\n$1\t2-beta\n$2\t3-gamma"

        # Shifting slots: $2 now sorts between $0 and $1 (equal indexes keep
        # tmux's name order) and wants $1's current name, so both pass through
        # temporary names while $0 is not renamed at all.
        def shift_slots():
            tmux("rename-session", "-t", "$2", "1-beta")
            tmux("rename-session", "-t", "$1", "2-beta")
            return tmux("list-sessions", "-F", "#{session_id}\t#{session_name}")

        shift_slots()
        rename_log.unlink()
        manager("ensure", extra_env=rename_env)
        assert sorted(rename_targets()) == ["$1", "$1", "$2", "$2"], rename_targets()
        assert tmux("list-sessions", "-F", "#{session_id}\t#{session_name}") == "$0\t1-alpha\n$2\t2-beta\n$1\t3-beta"

        for phase in ("temporary", "final"):
            before = shift_slots()
            once.unlink(missing_ok=True)
            failure_env = dict(rename_env, TMUX_TEST_FAIL_TARGET="$1", TMUX_TEST_FAIL_PHASE=phase)
            result = manager("ensure", check=False, extra_env=failure_env)
            assert result.returncode != 0 and "injected rename failure" in result.stderr
            assert tmux("list-sessions", "-F", "#{session_id}\t#{session_name}") == before
        tmux("rename-session", "-t", "$2", "3-gamma")
        tmux("rename-session", "-t", "$1", "2-beta")

        vanished = tmux("new-session", "-d", "-s", "vanishing", "-P", "-F", "#{session_id}", "/bin/sleep 120")
        once.unlink(missing_ok=True)
        manager("ensure", extra_env=dict(rename_env, TMUX_TEST_VANISH_ID=vanished))
        assert vanished not in tmux("list-sessions", "-F", "#{session_id}").splitlines()
        assert "__dotfiles_" not in tmux("list-sessions", "-F", "#{session_name}")

        # The default server context may be gamma; the supplied IDs must win.
        manager("rename", "renamed alpha", "--session", "$0")
        assert tmux("display-message", "-p", "-t", "$0", "#{session_name}") == "1-renamed alpha"
        assert tmux("display-message", "-p", "-t", "$2", "#{session_name}") == "3-gamma"
        manager("move-window-to", "2", "--session", "$0", "--window", source)
        assert tmux("display-message", "-p", "-t", source, "#{session_id}") == "$1"
        assert tmux("display-message", "-p", "-t", "@2", "#{session_id}") == "$2"
        before = tmux("list-windows", "-a", "-F", "#{session_id} #{window_id}")
        assert manager("move-window-to", "2", check=False).returncode != 0
        assert manager("move-window-to", "2", "--session", "$0", "--window", "@9999", check=False).returncode != 0
        assert tmux("list-windows", "-a", "-F", "#{session_id} #{window_id}") == before

        for index in range(4, 11):
            tmux("new-session", "-d", "-s", f"{index}-slot{index}", "/bin/sleep 120")
        names = [line.split("::", 1)[1] for line in manager("list").stdout.splitlines()]
        assert [int(name.split("-", 1)[0]) for name in names] == list(range(1, 11))
        status = subprocess.run(
            ["/bin/bash", str(ROOT / "home/.config/tmux/tmux-status/left.sh"), "$0", "160"],
            env=env, capture_output=True, text=True, check=True,
        ).stdout
        assert status.index("slot9") < status.index("slot10")
        assert "#[fg=#1d1f21,bg=#b294bb] renamed alpha " in status

        # Capture the system clipboard without touching the user's real clipboard.
        shim = work / "bin"
        shim.mkdir()
        clipboard = work / "clipboard"
        (shim / "pbcopy").write_text(f"#!/bin/sh\n/bin/cat > {shlex.quote(str(clipboard))}\n")
        (shim / "pbcopy").chmod(0o755)
        # copy-pipe runs its command from the server environment, not the caller's.
        tmux("set-environment", "-g", "PATH", f"{shim}:{env['PATH']}")
        tmux("set", "-g", "mode-keys", "vi")
        tmux("set", "-g", "history-limit", "30000")
        copy_bindings = work / "copy-mode.conf"
        copy_bindings.write_text("".join(
            line for line in (ROOT / "home/.tmux.conf").read_text().splitlines(keepends=True)
            if line.startswith("bind-key -T copy-mode-vi ")
        ))
        tmux("source-file", str(copy_bindings))
        fillers = (
            ("mixed", [f"line {index} literal #{{session_name}} 中文 \x1b[1mbold" for index in range(60)]),
            ("large", ["x" * 100] * 20_000),
        )
        for name, lines in fillers:
            # Both fillers overflow the 50-row pane, so history-bottom lands on
            # the empty cursor row below the last printed line.
            assert len(lines) > 50
            text = work / f"{name}.txt"
            text.write_text("\n".join(lines) + "\n")
            tmux("new-session", "-d", "-s", name, "-x", "200", "-y", "50", f"/bin/cat {shlex.quote(str(text))}; /bin/sleep 120")
            scrolled = str(len(lines) + 1 - 50)
            deadline = time.monotonic() + 10
            while tmux("display-message", "-p", "-t", name, "#{history_size}") != scrolled:
                assert time.monotonic() < deadline, "pane output did not settle"
                time.sleep(0.05)
            tmux("copy-mode", "-t", name)
            tmux("send-keys", "-t", name, "-X", "history-top")
            tmux("send-keys", "-t", name, "-X", "start-of-line")
            tmux("send-keys", "-t", name, "v")
            tmux("send-keys", "-t", name, "-X", "history-bottom")
            tmux("send-keys", "-t", name, "-X", "cursor-up")
            tmux("send-keys", "-t", name, "-X", "end-of-line")
            tmux("delete-buffer", check=False)
            clipboard.unlink(missing_ok=True)
            tmux("send-keys", "-t", name, "y")
            # The pane renders the escape as bold; the copied text keeps only the characters.
            expected = "\n".join(line.replace("\x1b[1m", "") for line in lines).encode()
            deadline = time.monotonic() + 10
            while not clipboard.exists() or clipboard.read_bytes() != expected:
                assert time.monotonic() < deadline, f"{name}: clipboard never matched"
                time.sleep(0.05)
            assert tmux("display-message", "-p", "-t", name, "#{pane_in_mode}") == "0"
            buffers = tmux("list-buffers", "-F", "#{buffer_size}").splitlines()
            assert buffers == [str(len(expected))], buffers
            assert subprocess.run(base + ["save-buffer", "-"], capture_output=True, check=True).stdout == expected
        print("tmux routing, ordering, and clipboard fixtures passed.")
    finally:
        tmux("kill-server", check=False)
