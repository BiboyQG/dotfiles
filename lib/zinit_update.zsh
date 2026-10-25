zinit_update_succeeded() {
  local update_log="$1"
  local exit_code="$2"
  # Bulk updates can exit 1 from their final completion refresh, before printing
  # a summary. Check diagnostics here and each Git checkout below instead.
  (( exit_code == 0 || exit_code == 1 )) || return 1
  python3 - "$update_log" <<'PY'
import re
import sys
from pathlib import Path

text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", Path(sys.argv[1]).read_text())
text = re.sub(r"\{[a-z0-9_-]+\}", "", text)
# zinit lists each new upstream commit as "<date> <hash> <subject>"; commit
# subjects such as "Fix error: ..." are not diagnostics.
text = re.sub(r"(?m)^\d{4}-\d{2}-\d{2} [0-9a-f]{7,}\b.*$", "", text)
failures = re.compile(
    r"(?im)(?:^|\s)(?:fatal:|error(?:\s*#?\d+)?:|curl:\s*\(\d+\)|"
    r"command not found:|permission denied|clone failed|download failed)|"
    r"warning:.*(?:update|hook).*returned|could not resolve|unable to access|"
    r"not possible to fast-forward|failed to (?:connect|download|fetch|update)"
)
sys.exit(1 if failures.search(text) else 0)
PY
}

verify_zinit_checkouts() {
  local plugins_dir="$1"
  local update_log="$2"
  local plugin upstream plugin_id plain_log
  local verified=0
  # zinit colors plugin names when $TERM has a color terminfo entry. BSD sed
  # rejects these byte ranges in UTF-8 locales.
  plain_log="$(LC_ALL=C sed -E $'s,\e\\[[0-?]*[ -/]*[@-~],,g' "$update_log")" || return 1
  for plugin in "$plugins_dir"/*(N/); do
    [[ -d "$plugin/.git" ]] || continue
    plugin_id="${plugin:t}"
    plugin_id="${plugin_id//---//}"
    if [[ "$plain_log" != *"Updating $plugin_id"* ]]; then
      printf "Zinit did not reach plugin: %s\n" "$plugin_id" >&2
      return 1
    fi
    upstream="$(git -C "$plugin" rev-parse --verify '@{upstream}' 2>/dev/null)" || {
      printf "Cannot verify zinit plugin upstream: %s\n" "$plugin" >&2
      return 1
    }
    if [[ "$(git -C "$plugin" rev-parse HEAD)" != "$upstream" ]]; then
      printf "Zinit plugin did not reach its fetched upstream: %s\n" "$plugin" >&2
      return 1
    fi
    verified=$((verified + 1))
  done
  (( verified > 0 ))
}
