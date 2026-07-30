typeset -U path PATH fpath FPATH

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
typeset +x FPATH

path=("$HOME/bin" "$HOME/.local/bin" $path)

[[ -r "$HOME/.zprofile.local" ]] && source "$HOME/.zprofile.local"
