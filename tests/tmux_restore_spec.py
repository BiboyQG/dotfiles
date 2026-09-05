"""Check restore/numbering coordination without touching real tmux state."""
import os
import io
import shlex
import shutil
import subprocess
import sys
import tempfile
import tarfile
import time
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
MANAGER = ROOT / "home/.config/tmux/scripts/session_manager.py"
STARTUP = ROOT / "home/.config/tmux/scripts/startup_restore.sh"
PLUGINS = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None


def write_snapshot(work, saved):
    saved.mkdir(parents=True)
    lines = []
    with tarfile.open(saved / "pane_contents.tar.gz", "w:gz") as archive:
        for name in ("1-alpha", "2-beta"):
            for pane in ("1", "2"):
                lines.append("\t".join((
                    "pane", name, "1", "1", "*", pane, "fixture", ":" + str(work),
                    "1" if pane == "1" else "0", "sh", ":",
                )))
                contents = b"saved pane contents\n"
                entry = tarfile.TarInfo(f"pane_contents/pane-{name}:1.{pane}")
                entry.size = len(contents)
                archive.addfile(entry, io.BytesIO(contents))
            lines.append("\t".join((
                "window", name, "1", ":saved-" + name, "1", ":*", "even-horizontal", "off",
            )))
    (saved / "last").write_text("\n".join(lines) + "\n")


@contextmanager
def server():
    with tempfile.TemporaryDirectory(prefix="dotfiles-tmux-restore-") as directory:
        work = Path(directory)
        socket = str(work / "tmux.sock")
        env = dict(os.environ, HOME=str(work), XDG_DATA_HOME=str(work / "data"))
        base = ["tmux", "-S", socket]

        def tmux(*args, check=True):
            return subprocess.run(
                base + list(args), env=env, capture_output=True, text=True, check=check,
            ).stdout.strip()

        def manager(*args):
            return subprocess.run(
                [sys.executable, str(MANAGER), *args], env=env,
                capture_output=True, text=True, check=True,
            ).stdout.strip()

        try:
            tmux("-f", "/dev/null", "new-session", "-d", "-s", "0", "/bin/sleep 120")
            env["TMUX"] = f"{socket},{tmux('display-message', '-p', '#{pid}')},0"
            tmux("set", "-g", "default-shell", "/bin/sh")
            tmux("set", "-g", "default-command", "/bin/sh")
            tmux("set", "-g", "base-index", "1")
            tmux("set", "-g", "pane-base-index", "1")
            tmux("set", "-g", "@resurrect-dir", str(work / "saved"))
            tmux("set", "-g", "@resurrect-processes", "false")
            command = f"{shlex.quote(sys.executable)} {shlex.quote(str(MANAGER))}"
            tmux("set", "-g", "@resurrect-hook-pre-restore-all", f"{command} restore-begin")
            tmux("set", "-g", "@resurrect-hook-post-restore-all", f"{command} restore-end")
            manager("startup-prepare")
            tmux("set-hook", "-g", "session-created[100]", f"run-shell -b {shlex.quote(command + ' created')}")
            tmux("set-hook", "-g", "session-closed[100]", f"run-shell -b {shlex.quote(command + ' ensure')}")
            manager("created")
            assert tmux("list-sessions", "-F", "#{session_name}") == "0"
            yield work, env, tmux, manager
        finally:
            tmux("kill-server", check=False)


if PLUGINS is None:
    for outcome in ("restored", "no-snapshot", "multiple-servers", "opt-out", "missing-plugin", "failed"):
        with server() as (work, env, tmux, manager):
            # Only external restore eligibility is mocked; lifecycle commands and
            # asynchronous tmux hooks run against the real disposable server.
            helpers = work / ".tmux/plugins/tmux-continuum/scripts/helpers.sh"
            helpers.parent.mkdir(parents=True)
            helpers.write_text("another_tmux_server_running_on_startup() { [[ ${TEST_MULTIPLE_SERVERS:-no} == yes ]]; }\n")
            restore = work / "restore.sh"
            marker = work / "restored"
            restore.write_text(
                "#!/bin/bash\nset -euo pipefail\n"
                "[[ ${TEST_RESTORE_OUTCOME:-} != no-snapshot ]] || exit 0\n"
                "eval \"$(tmux show-option -gqv @resurrect-hook-pre-restore-all)\"\n"
                "[[ ${TEST_RESTORE_OUTCOME:-} != failed ]] || exit 7\n"
                "tmux new-session -d -s 1-alpha /bin/sleep 120\n"
                f"{shlex.quote(sys.executable)} {shlex.quote(str(MANAGER))} created\n"
                "tmux new-window -d -t 1-alpha:2 -n saved-alpha /bin/sleep 120\n"
                "tmux kill-session -t 0\n"
                "eval \"$(tmux show-option -gqv @resurrect-hook-post-restore-all)\"\n"
                f"touch {shlex.quote(str(marker))}\n"
            )
            restore.chmod(0o755)
            tmux("set", "-g", "@resurrect-restore-script-path", str(restore))
            env["TEST_RESTORE_OUTCOME"] = outcome
            if outcome == "multiple-servers":
                env["TEST_MULTIPLE_SERVERS"] = "yes"
            if outcome == "opt-out":
                (work / "tmux_no_auto_restore").touch()
            if outcome == "missing-plugin":
                helpers.unlink()
            result = subprocess.run(["/bin/bash", str(STARTUP)], env=env, capture_output=True, text=True)
            assert result.returncode == (7 if outcome == "failed" else 0), result.stderr
            assert tmux("show-option", "-gqv", "@dotfiles-session-startup") == "complete"
            assert tmux("show-option", "-gqv", "@dotfiles-session-restoring") == "off"
            assert marker.exists() == (outcome == "restored")
            expected = "1-alpha" if outcome == "restored" else "1-0"
            assert tmux("list-sessions", "-F", "#{session_name}") == expected
            # Reload must not claim another restore or rename existing sessions.
            tmux("rename-session", "-t", expected, "kept-on-reload")
            manager("startup-prepare")
            subprocess.run(["/bin/bash", str(STARTUP)], env=env, check=True)
            assert tmux("list-sessions", "-F", "#{session_name}") == "kept-on-reload"


    with server() as (work, env, tmux, manager):
        manager("startup-finish")
        manager("restore-begin")
        tmux("new-session", "-d", "-s", "10-restored", "/bin/sleep 120")
        manager("created")
        manager("rename", "must-not-change", "--session", "$0")
        assert tmux("list-sessions", "-F", "#{session_name}") == "1-0\n10-restored"
        manager("restore-end")
        assert tmux("list-sessions", "-F", "#{session_name}") == "1-0\n2-restored"

    with server() as (work, env, tmux, manager):
        # Loading the new config on an older server must not restore over work.
        tmux("set", "-gu", "@dotfiles-session-startup")
        tmux("set", "-g", "@continuum-restore-max-delay", "0")
        manager("startup-prepare")
        assert manager("startup-claim") == ""
        assert tmux("list-sessions", "-F", "#{session_name}") == "0"


if PLUGINS is not None:
    restore = PLUGINS / "tmux-resurrect/scripts/restore.sh"
    assert restore.is_file(), restore
    with server() as (work, env, tmux, manager):
        saved = work / "saved"
        write_snapshot(work, saved)
        assert manager("startup-claim") == "claimed"
        # Invoke the actual installed plugin, independent of other live servers.
        # Eligibility gates are covered above without consulting user processes.
        result = subprocess.run(["/bin/bash", str(restore)], env=env, capture_output=True, text=True, check=True)
        assert "can't find" not in result.stderr, result.stderr
        manager("startup-finish")
        actual = tmux("list-windows", "-a", "-F", "#{session_name}:#{window_name}:#{window_panes}")
        assert actual == "1-alpha:saved-1-alpha:2\n2-beta:saved-2-beta:2", actual
        for name in ("1-alpha", "2-beta"):
            positions = tmux("list-panes", "-t", name, "-F", "#{pane_left}:#{pane_top}").splitlines()
            assert positions[0] == "0:0" and positions[1].endswith(":0"), positions
            assert int(positions[1].split(":", 1)[0]) > 0, positions
        print("Installed tmux-resurrect restored session names, window names, panes, and layouts.")

    # Exercise configuration loading before the initial session exists, not just
    # source-file against an already-created server. All plugin data stays local.
    with tempfile.TemporaryDirectory(prefix="dotfiles-tmux-startup-") as directory:
        work = Path(directory)
        (work / ".config").mkdir()
        plugin_dir = work / ".tmux/plugins"
        plugin_dir.mkdir(parents=True)
        (work / ".config/tmux").symlink_to(ROOT / "home/.config/tmux", target_is_directory=True)
        for plugin in PLUGINS.iterdir():
            if plugin.name == "tmux-continuum":
                shutil.copytree(plugin, plugin_dir / plugin.name, ignore=shutil.ignore_patterns(".git"))
            else:
                (plugin_dir / plugin.name).symlink_to(plugin, target_is_directory=plugin.is_dir())
        # The test server is deliberately additional to the user's real server.
        # Override only that eligibility check in a temporary plugin copy.
        helper = plugin_dir / "tmux-continuum/scripts/helpers.sh"
        with helper.open("a") as stream:
            stream.write("\nanother_tmux_server_running_on_startup() { return 1; }\n")
        (work / ".tmux.conf").symlink_to(ROOT / "home/.tmux.conf")
        write_snapshot(work, work / "data/tmux/resurrect")
        env = dict(
            os.environ, HOME=str(work), XDG_CONFIG_HOME=str(work / ".config"),
            XDG_DATA_HOME=str(work / "data"), XDG_CACHE_HOME=str(work / "cache"),
        )
        base = ["tmux", "-S", str(work / "tmux.sock")]

        def tmux_config(*args, check=True):
            return subprocess.run(
                base + list(args), env=env, capture_output=True, text=True, check=check, timeout=15,
            )

        try:
            result = tmux_config("-f", str(work / ".tmux.conf"), "new-session", "-d", "/usr/bin/tail -f /dev/null")
            assert not result.stdout and not result.stderr, result.stdout + result.stderr
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                name = tmux_config("list-sessions", "-F", "#{session_name}").stdout.strip()
                state = tmux_config("show-option", "-gqv", "@dotfiles-session-startup").stdout.strip()
                if name == "1-alpha\n2-beta" and state == "complete":
                    break
                time.sleep(0.05)
            assert name == "1-alpha\n2-beta", name
            assert state == "complete", state
            actual = tmux_config("list-windows", "-a", "-F", "#{session_name}:#{window_name}:#{window_panes}").stdout.strip()
            assert actual == "1-alpha:saved-1-alpha:2\n2-beta:saved-2-beta:2", actual
            tmux_config("rename-session", "-t", "1-alpha", "kept-on-reload")
            tmux_config("source-file", str(work / ".tmux.conf"))
            assert tmux_config("show-option", "-gqv", "@dotfiles-session-startup").stdout.strip() == "complete"
            assert tmux_config("list-sessions", "-F", "#{session_name}").stdout.strip() == "2-beta\nkept-on-reload"
            print("Deployed tmux configuration restored a new server without a placeholder and reloaded safely.")
        finally:
            tmux_config("kill-server", check=False)

if PLUGINS is None:
    print("tmux restore lifecycle, skip, failure, manual restore, and reload fixtures passed.")
