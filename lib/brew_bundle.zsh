# The marketing name ("Mac Studio", "MacBook Pro"); hw.model would need the
# model identifier of every generation.
mac_model_name() {
  system_profiler SPHardwareDataType -json \
    | plutil -extract 'SPHardwareDataType.0.machine_name' raw -o - -
}

brew_bundle_cask_skip() {
  local skip_value="${HOMEBREW_BUNDLE_CASK_SKIP:-}"
  local pair cask app model
  local -a unmanaged_apps=(
    'visual-studio-code:/Applications/Visual Studio Code.app'
    'mos:/Applications/Mos.app'
  )

  for pair in "${unmanaged_apps[@]}"; do
    cask="${pair%%:*}"
    app="${pair#*:}"
    if [[ -d "$app" ]] && ! brew list --cask "$cask" >/dev/null 2>&1 \
      && [[ " $skip_value " != *" $cask "* ]]; then
      skip_value+="${skip_value:+ }$cask"
    fi
  done

  # Mos smooths the mouse wheel on the Mac Studio; the MacBook Pro has no
  # mouse and scrolls with Homerow.
  if ! model="$(mac_model_name)" || [[ -z "$model" ]]; then
    printf 'Could not read the Mac model name for the Mos cask skip.\n' >&2
    return 1
  fi
  if [[ "$model" != "Mac Studio" && " $skip_value " != *" mos "* ]]; then
    skip_value+="${skip_value:+ }mos"
  fi
  print -r -- "$skip_value"
}

brew_bundle_report_extras() {
  local brewfile="$1"
  local output exit_code=0

  # Cleanup lists what is installed but not declared; it ignores
  # HOMEBREW_BUNDLE_CASK_SKIP, so the skip list is not computed here.
  output="$(brew bundle cleanup --file="$brewfile" --verbose </dev/null 2>&1)" || exit_code=$?
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
