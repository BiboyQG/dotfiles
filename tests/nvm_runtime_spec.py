"""Cold-shell NVM alias fallback fixtures."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
source = (ROOT / "home/.zshrc").read_text()
nvm_block = source.split("# Node Version Manager\n", 1)[1].split("# Cargo", 1)[0]
nvm_block = nvm_block.replace('export NVM_DIR="$HOME/.nvm"', 'export NVM_DIR="$1"')

with tempfile.TemporaryDirectory(prefix="dotfiles-shell-spec-") as directory:
    work = Path(directory)
    (work / "alias").mkdir()
    binary_dir = work / "versions/node/v26.5.1/bin"
    binary_dir.mkdir(parents=True)
    (binary_dir / "node").write_text("#!/bin/sh\necho fixture-node\n")
    (binary_dir / "node").chmod(0o755)
    (work / "nvm.sh").write_text('''
[[ "$1" == --no-use ]] || return 1
print loaded >> "$NVM_DIR/load-log"
nvm() { print v26.5.1; }
''')
    script = nvm_block + '\ncommand -v node\n(( $+functions[nvm] ))\n(( ! $+functions[nvm_ls] ))\n'
    for alias in ("v26.5.1", "node", "lts/*", "26"):
        (work / "alias/default").write_text(alias + "\n")
        result = subprocess.run(
            ["zsh", "-dfc", script, "nvm-fixture", str(work)],
            env=dict(os.environ, PATH="/usr/bin:/bin"), capture_output=True, text=True, check=True,
        )
        assert result.stdout.strip() == str(binary_dir / "node")
        if alias == "v26.5.1":
            assert not (work / "load-log").exists(), "concrete default loaded nvm eagerly"
    assert len((work / "load-log").read_text().splitlines()) == 3

    print("NVM lazy-loading fixtures passed.")
