"""Ensure the checker detects syntax errors beyond the first shell file."""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
source = (ROOT / "check.sh").read_text()
block = source.split('log "Checking shell syntax"\n', 1)[1].split(
    'log "Checking public IP helper behavior"', 1
)[0]
paths = {"setup.sh", "check.sh", "home/.p10k.zsh", "home/.zprofile", "home/.zshrc",
         "home/bin/abs", "home/bin/ip", "home/.config/aerospace/scripts/resize-edge"}
for pattern in ("lib/*.zsh", "home/.config/sketchybar/scripts/*.sh",
                "home/.config/tmux/scripts/*.sh", "home/.config/tmux/tmux-status/*.sh"):
    paths.update(str(path.relative_to(ROOT)) for path in ROOT.glob(pattern))

with tempfile.TemporaryDirectory(prefix="dotfiles-syntax-spec-") as directory:
    work = Path(directory)
    for name in paths:
        path = work / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("true\n")

    def check():
        return subprocess.run(["zsh", "-dfc", "set -e\n" + block], cwd=work,
                              text=True, capture_output=True)

    assert check().returncode == 0
    for name in ("home/.zprofile", "home/.config/tmux/tmux-status/left.sh"):
        (work / name).write_text("if then\n")
        result = check()
        assert result.returncode != 0 and name in result.stderr, (name, result)
        (work / name).write_text("true\n")
    print("Shell syntax coverage fixtures passed.")
