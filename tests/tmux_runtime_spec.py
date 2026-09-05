"""Exercise session routing and clipboard bytes against a disposable tmux server."""
import os
import shlex
import subprocess
import sys
import tempfile
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

        def manager(*args, check=True):
            return subprocess.run(
                [sys.executable, str(MANAGER), *args], env=env,
                capture_output=True, text=True, check=check,
            )

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
        copy_env = dict(env, PATH=f"{shim}:{env['PATH']}")
        for data in (b"first\nsecond\n\n", b"first\rsecond\n", b"x" * 2_000_000 + b"\n", b""):
            subprocess.run(
                ["/bin/bash", str(ROOT / "home/.config/tmux/scripts/copy_to_clipboard.sh")],
                input=data, env=copy_env, check=True,
            )
            assert clipboard.read_bytes() == data
            if data:
                copied = subprocess.run(base + ["save-buffer", "-"], capture_output=True, check=True).stdout
                assert copied == data
        print("tmux routing, ordering, and clipboard fixtures passed.")
    finally:
        tmux("kill-server", check=False)
