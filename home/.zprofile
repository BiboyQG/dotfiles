typeset -U path PATH

# Static equivalent of `eval "$(brew shellenv)"` for the Apple Silicon prefix;
# .zshrc adds the zsh site-functions directory to fpath.
# The eval forks bash and ps to print constant text (~17 ms per login shell).
if [[ -x /opt/homebrew/bin/brew ]]; then
  export HOMEBREW_PREFIX=/opt/homebrew
  export HOMEBREW_CELLAR=/opt/homebrew/Cellar
  export HOMEBREW_REPOSITORY=/opt/homebrew
  path=(/opt/homebrew/bin /opt/homebrew/sbin $path)
  export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"
fi

path=("$HOME/bin" "$HOME/.local/bin" $path)

[[ -r "$HOME/.zprofile.local" ]] && source "$HOME/.zprofile.local"
