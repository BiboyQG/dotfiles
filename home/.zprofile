typeset -U path PATH fpath FPATH

# Static equivalent of `eval "$(brew shellenv)"` for the Apple Silicon prefix.
# The eval forks bash and ps to print constant text (~17 ms per login shell).
if [[ -x /opt/homebrew/bin/brew ]]; then
  export HOMEBREW_PREFIX=/opt/homebrew
  export HOMEBREW_CELLAR=/opt/homebrew/Cellar
  export HOMEBREW_REPOSITORY=/opt/homebrew
  fpath[1,0]=/opt/homebrew/share/zsh/site-functions
  path=(/opt/homebrew/bin /opt/homebrew/sbin $path)
  [ -z "${MANPATH-}" ] || { export MANPATH="${MANPATH%"${MANPATH##*[!:]}"}"; export MANPATH=":${MANPATH#"${MANPATH%%[!:]*}"}"; }
  export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"
fi
typeset +x FPATH

path=("$HOME/bin" "$HOME/.local/bin" $path)

[[ -r "$HOME/.zprofile.local" ]] && source "$HOME/.zprofile.local"
