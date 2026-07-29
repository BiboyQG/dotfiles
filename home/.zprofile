typeset -U path PATH

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

path=("$HOME/bin" "$HOME/.local/bin" $path)

[[ -r "$HOME/.zprofile.local" ]] && source "$HOME/.zprofile.local"
