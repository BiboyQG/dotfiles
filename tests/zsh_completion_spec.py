"""Replay deferred plugin completions after fresh and cached compinit."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
source = (ROOT / "home/.zshrc").read_text()
completion_block = "autoload -Uz compinit\n" + source.split("autoload -Uz compinit\n", 1)[1].split(
    "# To customize prompt", 1
)[0]

# Model Zinit's deferred-compdef contract while using real compinit/compdef.
# This keeps the fixture independent of installed plugins and network access.
deferred_plugin = '''
typeset -ga ZINIT_COMPDEF_REPLAY
compdef() { ZINIT_COMPDEF_REPLAY+=("${(j: :)${(q)@}}"); }
compdef _git ggp=git-push
compdef _git gccd=git-clone
compdef _git gdv=git-diff
unfunction compdef
zinit() {
  [[ "$*" == 'cdreplay -q' ]] || return 1
  local definition
  for definition in "${ZINIT_COMPDEF_REPLAY[@]}"; do
    eval "compdef $definition" || return
  done
}
'''
inspect_completions = '''
for name in ggp gccd gdv; do
  print -r -- "$name:${_comps[$name]:-missing}:${_services[$name]:-missing}"
done
'''

with tempfile.TemporaryDirectory(prefix="dotfiles-completion-spec-") as directory:
    work = Path(directory)
    env = dict(os.environ, HOME=str(work), ZDOTDIR=str(work), PATH="/usr/bin:/bin")
    env.pop("FPATH", None)

    def run(prefix, suffix):
        result = subprocess.run(
            ["zsh", "-dfc", prefix + completion_block + suffix],
            env=env, capture_output=True, text=True, check=True,
        )
        assert not result.stderr, result.stderr
        return result.stdout.splitlines()

    expected = ["ggp:_git:git-push", "gccd:_git:git-clone", "gdv:_git:git-diff"]
    assert run(deferred_plugin, inspect_completions) == expected, "fresh compinit lost deferred completions"
    dump, = (path for path in work.glob(".zcompdump-[0-9]*") if not path.name.endswith(".fpath"))
    dump_state = (dump.stat().st_ino, dump.stat().st_mtime_ns, dump.read_bytes())
    assert run(deferred_plugin, inspect_completions) == expected, "cached compinit lost deferred completions"
    assert (dump.stat().st_ino, dump.stat().st_mtime_ns, dump.read_bytes()) == dump_state, "warm shell rebuilt compinit"
    assert run("", 'print -r -- "${_comps[git]:-missing}"\n') == ["_git"], "compinit requires Zinit"

    print("Zsh fresh/cached completion replay fixtures passed.")
