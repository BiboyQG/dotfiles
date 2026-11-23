typeset -U path PATH fpath FPATH
unset NO_COLOR

[[ -t 0 ]] && stty -ixon

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
fpath=(/opt/homebrew/share/zsh/site-functions $fpath)
[[ -d "$HOME/.docker/completions" ]] && fpath=("$HOME/.docker/completions" $fpath)

if [[ -r "$ZINIT_HOME/zinit.zsh" ]]; then
	source "$ZINIT_HOME/zinit.zsh"

	ZSH_AUTOSUGGEST_MANUAL_REBIND=1
	zinit light-mode depth=1 for \
		zsh-users/zsh-syntax-highlighting \
		zsh-users/zsh-completions \
		zsh-users/zsh-autosuggestions \
		Aloxaf/fzf-tab
	zinit wait lucid for OMZL::git.zsh OMZP::git
else
	print -u2 "zinit is not installed; rerun the dotfiles setup script"
fi

autoload -Uz compinit
() {
	setopt localoptions extendedglob
	local dump="${ZDOTDIR:-$HOME}/.zcompdump-${ZSH_VERSION}"
	if [[ -f "$dump" && -z "$dump"(#qN.mh+24) ]]; then
		compinit -C -d "$dump"
	else
		compinit -d "$dump"
	fi
}

if (( $+functions[zinit] )); then
	zinit cdreplay -q
fi

bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^x^e' edit-command-line

HISTSIZE=10000
SAVEHIST=$HISTSIZE
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_find_no_dups

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --color=always --icons=always $realpath'

# Cache tool init scripts keyed on the resolved binary path (which in Homebrew
# includes the Cellar version) to avoid forking subprocesses on every shell start.
_cached_init() {
	local tool="$1"
	shift
	local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
	local cache="$cache_dir/$tool-init.zsh"
	local key="# ${commands[$tool]:A}"
	local stamp=""
	[[ -r "$cache" ]] && IFS= read -r stamp <"$cache"
	if [[ "$stamp" != "$key" ]]; then
		mkdir -p -- "$cache_dir" \
			&& { print -r -- "$key"; "$tool" "$@"; } >| "$cache.tmp.$$" \
			&& mv -f -- "$cache.tmp.$$" "$cache"
		rm -f -- "$cache.tmp.$$"
	fi
	[[ -r "$cache" ]] && source "$cache"
}
(( $+commands[starship] )) && _cached_init starship init zsh
(( $+commands[zoxide] )) && _cached_init zoxide init --cmd cd zsh
(( $+commands[fzf] )) && _cached_init fzf --zsh
(( $+commands[direnv] )) && _cached_init direnv hook zsh

alias ll="eza -alh --icons=auto --color=always"
alias s="fastfetch"
alias l="lazygit"
alias tn="tmux new -s"
alias ta="tmux attach"
alias tls="tmux ls"
alias c="claude"
alias codex="codex --dangerously-bypass-approvals-and-sandbox"
alias cat="bat"

alias -s md='$=EDITOR'
alias -s txt=bat
alias -s log=bat
alias -s py='$=EDITOR'
alias -s html=open

bindkey -s '^xgc' 'git commit -m ""\C-b'

function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

export EDITOR="zed --wait"

if [[ -r "$HOME/.cargo/env" ]]; then
	source "$HOME/.cargo/env"
fi
