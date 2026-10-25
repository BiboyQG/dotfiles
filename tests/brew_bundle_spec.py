"""Check the Mac Studio cask skip and the Homebrew dry-run report handling."""
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
# Every cask counts as Homebrew-managed, whatever the host has in /Applications.
[[ "$1 $2" == 'list --cask' ]] && exit 0
[[ "$*" == 'bundle cleanup --file=fixture.Brewfile --verbose' ]] || exit 91
read -r unexpected && exit 92
print -rn -- "$FIXTURE_OUTPUT"
print -rn -- "$FIXTURE_ERROR" >&2
exit "$FIXTURE_EXIT"
""")
    brew.chmod(0o755)
    system_profiler = work / "system_profiler"
    system_profiler.write_text("""#!/bin/zsh
[[ "$*" == 'SPHardwareDataType -json' ]] || exit 93
printf '{"SPHardwareDataType":[{"machine_name":"%s"}]}\\n' "$FIXTURE_MODEL"
exit "$FIXTURE_PROFILER_EXIT"
""")
    system_profiler.chmod(0o755)
    # The callers assign the result under set -euo pipefail, so a failed lookup
    # must stop the shell before anything is printed.
    skip_script = '''
set -euo pipefail
source "$1/lib/brew_bundle.zsh"
skip="$(brew_bundle_cask_skip)"
print -r -- "$skip"
'''
    skip_cases = (
        ("mac studio", "Mac Studio", 0, "", 0, ""),
        ("mac studio with preset skip", "Mac Studio", 0, "arc", 0, "arc"),
        ("macbook pro", "MacBook Pro", 0, "", 0, "mos"),
        ("macbook pro with preset skip", "MacBook Pro", 0, "arc", 0, "arc mos"),
        ("macbook pro already skipping mos", "MacBook Pro", 0, "mos", 0, "mos"),
        ("empty model name", "", 0, "", 1, ""),
        ("model lookup failure", "Mac Studio", 4, "", 1, ""),
    )
    for name, model, profiler_exit, preset, expected_code, expected_output in skip_cases:
        env = dict(os.environ, PATH=f"{work}:/usr/bin:/bin", FIXTURE_MODEL=model,
                   FIXTURE_PROFILER_EXIT=str(profiler_exit), HOMEBREW_BUNDLE_CASK_SKIP=preset)
        result = subprocess.run(["zsh", "-dfc", skip_script, "brew-fixture", str(ROOT)],
                                env=env, text=True, capture_output=True)
        assert result.returncode == expected_code, (name, result)
        assert result.stdout == (expected_output + "\n" if expected_code == 0 else ""), (name, result)
        assert ("Could not read the Mac model name" in result.stderr) == (expected_code != 0), (name, result)
    script = '''
source "$1/lib/brew_bundle.zsh"
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
                                env=env, text=True, capture_output=True, input="unexpected\n")
        assert result.returncode == expected, (name, result)
        assert ("audit did not complete" in result.stderr) == (expected != 0), (name, result)
    print("Homebrew cask skip and audit completion fixtures passed.")
