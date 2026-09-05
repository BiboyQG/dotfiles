"""Distinguish a complete Homebrew dry-run report from an audit failure."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
NOTICE = "Run `brew bundle cleanup --force` to make these changes.\n"

with tempfile.TemporaryDirectory(prefix="dotfiles-brew-spec-") as directory:
    work = Path(directory)
    brew = work / "brew"
    brew.write_text("""#!/bin/zsh
[[ "$HOMEBREW_BUNDLE_CASK_SKIP" == arc ]] || exit 90
[[ "$*" == 'bundle cleanup --file=fixture.Brewfile --verbose' ]] || exit 91
read -r unexpected && exit 92
print -rn -- "$FIXTURE_OUTPUT"
print -rn -- "$FIXTURE_ERROR" >&2
exit "$FIXTURE_EXIT"
""")
    brew.chmod(0o755)
    script = '''
source "$1/lib/brew_bundle.zsh"
brew_bundle_cask_skip() { print arc; }
brew_bundle_report_extras fixture.Brewfile
'''
    cases = (
        ("clean", 0, "", "", 0),
        ("extra formula", 1, "Would uninstall formulae:\nexample\n" + NOTICE, "", 0),
        ("extra tap", 1, "Would untap:\nexample/tap\n" + NOTICE, "", 0),
        ("load failure", 1, "", "Error: unable to load formula\n", 1),
        ("partial report", 1, "Would uninstall formulae:\nexample\n", "Error: interrupted\n", 1),
        ("unknown exit 1", 1, "unexpected output\n", "", 1),
        ("error after report", 1, "Would untap:\nexample/tap\n" + NOTICE, "Error: failed\n", 1),
        ("other failure", 2, "Would untap:\nexample/tap\n" + NOTICE, "", 2),
    )
    for name, code, output, error, expected in cases:
        env = dict(os.environ, PATH=f"{work}:/usr/bin:/bin", FIXTURE_OUTPUT=output,
                   FIXTURE_ERROR=error, FIXTURE_EXIT=str(code))
        result = subprocess.run(["zsh", "-dfc", script, "brew-fixture", str(ROOT)],
                                env=env, text=True, capture_output=True)
        assert result.returncode == expected, (name, result)
        assert ("audit did not complete" in result.stderr) == (expected != 0), (name, result)
    print("Homebrew audit completion and failure fixtures passed.")
