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
  local skip_value exit_code
  skip_value="$(brew_bundle_cask_skip)"

  HOMEBREW_BUNDLE_CASK_SKIP="$skip_value" \
    brew bundle cleanup --file="$brewfile" --verbose </dev/null || {
      exit_code=$?
      (( exit_code == 1 )) && return 0
      return "$exit_code"
    }
}
