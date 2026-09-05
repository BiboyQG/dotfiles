brew_bundle_cask_skip() {
  local skip_value="${HOMEBREW_BUNDLE_CASK_SKIP:-}"
  local pair cask app
  local -a unmanaged_apps=(
    'arc:/Applications/Arc.app'
    'visual-studio-code:/Applications/Visual Studio Code.app'
  )

  for pair in "${unmanaged_apps[@]}"; do
    cask="${pair%%:*}"
    app="${pair#*:}"
    if [[ -d "$app" ]] && ! brew list --cask "$cask" >/dev/null 2>&1 \
      && [[ " $skip_value " != *" $cask "* ]]; then
      skip_value+="${skip_value:+ }$cask"
    fi
  done
  print -r -- "$skip_value"
}

brew_bundle_report_extras() {
  local brewfile="$1"
  local skip_value output exit_code=0
  skip_value="$(brew_bundle_cask_skip)"

  output="$(HOMEBREW_BUNDLE_CASK_SKIP="$skip_value" \
    brew bundle cleanup --file="$brewfile" --verbose </dev/null 2>&1)" || exit_code=$?
  [[ -z "$output" ]] || print -r -- "$output"
  (( exit_code == 0 )) && return 0

  # Exit 1 also covers failures before the dry-run report is complete. Only
  # accept the completed report, including Homebrew's final action notice.
  if (( exit_code == 1 )) \
    && grep -Eq '^Would (uninstall .+|untap):$' <<<"$output" \
    && grep -Fxq 'Run `brew bundle cleanup --force` to make these changes.' <<<"$output" \
    && ! grep -Eq '^(Error:|fatal:)' <<<"$output"; then
    return 0
  fi
  printf 'WARN: Optional Homebrew cleanup audit did not complete (exit %s).\n' "$exit_code" >&2
  return "$exit_code"
}
