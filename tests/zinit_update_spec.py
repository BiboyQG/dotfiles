"""zinit diagnostics and plugin revision postflight fixtures."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="dotfiles-zinit-spec-") as directory:
    work = Path(directory)
    log = work / "update.log"
    cases = [
        ("Updating org/plugin\nThe update took 1 seconds\n", "0", True),
        ("Updating org/plugin\n", "1", True),
        ("Updating org/plugin\nThe update took 1 seconds\n", "2", False),
        ("Updating plugin\n", "0", False),
        ("Updating org/plugin\nfatal: Could not read from remote repository\n", "1", False),
        ("Updating org/plugin\ncurl: (28) Connection timed out\n", "0", False),
        ("Updating org/plugin\n\x1b[31mERROR:\x1b[0m Download failed.\n", "1", False),
        ("Updating org/plugin\n{u-warn}ERROR{b-warn}:{rst}No download tool detected\n", "1", False),
        ("Updating org/plugin\nWarning: org/plugin update returned 1\n", "0", False),
    ]
    for text, code, expected in cases:
        log.write_text(text)
        result = subprocess.run(
            ["zsh", "-dfc", 'source "$1"; zinit_update_succeeded "$2" "$3"',
             "zinit-fixture", str(ROOT / "lib/zinit_update.zsh"), str(log), code],
            capture_output=True, text=True,
        )
        assert (result.returncode == 0) == expected, text

    plugins = work / "plugins"
    checkout = plugins / "org---plugin"
    checkout.mkdir(parents=True)
    git_env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")

    def git(*args, input=None):
        return subprocess.run(
            ["git", "-C", str(checkout), *args], env=git_env,
            input=input, capture_output=True, text=True, check=True,
        ).stdout.strip()

    git("init", "-q", "-b", "main")
    git("config", "user.name", "Fixture")
    git("config", "user.email", "fixture@example.invalid")
    git("commit", "--allow-empty", "-qm", "initial")
    git("remote", "add", "origin", str(work / "unused-remote"))
    git("update-ref", "refs/remotes/origin/main", "HEAD")
    git("branch", "--set-upstream-to", "origin/main")

    def verified():
        result = subprocess.run(
            ["zsh", "-dfc", 'source "$1"; verify_zinit_checkouts "$2" "$3"',
             "zinit-fixture", str(ROOT / "lib/zinit_update.zsh"), str(plugins), str(log)],
            env=git_env, capture_output=True, text=True,
        )
        return result.returncode == 0

    log.write_text("Updating org/plugin\n")
    assert verified(), "completed plugin failed postflight"
    log.write_text("Updating org/other\n")
    assert not verified(), "update which exited early passed postflight"
    log.write_text("Updating org/plugin\n")
    ahead = git("commit-tree", "HEAD^{tree}", "-p", "HEAD", input="upstream\n")
    git("update-ref", "refs/remotes/origin/main", ahead)
    assert not verified(), "plugin behind fetched upstream passed postflight"
    print("zinit failure and postflight fixtures passed.")
