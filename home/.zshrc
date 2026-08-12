typeset -U path PATH
unset NO_COLOR

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
typeset -U fpath FPATH
if [[ -d /opt/homebrew/share/zsh/site-functions ]]; then
	fpath=(/opt/homebrew/share/zsh/site-functions $fpath)
fi
typeset +x FPATH

if [[ -r "$ZINIT_HOME/zinit.zsh" ]]; then
	source "$ZINIT_HOME/zinit.zsh"

	zinit ice depth=1
	zinit light romkatv/powerlevel10k
	zinit light zsh-users/zsh-syntax-highlighting
	zinit light zsh-users/zsh-completions
	zinit light zsh-users/zsh-autosuggestions
	zinit light Aloxaf/fzf-tab
	zinit snippet OMZP::git
else
	print -u2 "zinit is not installed; rerun the dotfiles setup script"
fi

if [[ -d "$HOME/.docker/completions" ]]; then
	fpath=("$HOME/.docker/completions" $fpath)
fi

autoload -Uz compinit
zmodload zsh/datetime
zmodload zsh/stat
zcompdump="${ZDOTDIR:-$HOME}/.zcompdump-${ZSH_VERSION}"
zcompdump_fpath="${zcompdump}.fpath"
zcompdump_tmp="${zcompdump}.tmp.$$"
# Rebuild after completion-path changes and periodically rerun compaudit.
typeset -Ua zcompdirs
typeset -a zcompstat
zcompdirs=()
zcompstat=()
zcompinit_refresh=0
zcompdump_mtime=0
for zcompdir in "$fpath[@]"; do
	[[ -d "$zcompdir" ]] && zcompdirs+=("$zcompdir")
done
zcomp_signature="${ZSH_VERSION}"$'\n'"${(F)zcompdirs}"
[[ -f "$zcompdump" ]] && zcompdump_mtime="$(zstat +mtime -- "$zcompdump" 2>/dev/null)"
if [[ ! -f "$zcompdump" ]] \
	|| [[ ! -f "$zcompdump_fpath" ]] \
	|| [[ "$(<"$zcompdump_fpath")" != "$zcomp_signature" ]] \
	|| (( EPOCHSECONDS - zcompdump_mtime > 86400 )) \
	|| ! zstat -A zcompstat +ctime -- "$zcompdump" "$zcompdirs[@]" 2>/dev/null; then
	zcompinit_refresh=1
else
	zcompdump_ctime="${zcompstat[1]}"
	for zcompctime in "${zcompstat[@]:1}"; do
		if (( zcompctime > zcompdump_ctime )); then
			zcompinit_refresh=1
			break
		fi
	done
fi
if (( zcompinit_refresh )); then
	rm -f -- "$zcompdump_tmp"
	if compinit -d "$zcompdump_tmp" \
		&& [[ -f "$zcompdump_tmp" ]] \
		&& mv -f -- "$zcompdump_tmp" "$zcompdump"; then
		print -r -- "$zcomp_signature" >| "$zcompdump_fpath" 2>/dev/null || true
	else
		rm -f -- "$zcompdump_tmp"
	fi
	_comp_dumpfile="$zcompdump"
else
	compinit -C -d "$zcompdump"
fi
unset zcomp_signature zcompctime zcompdir zcompdirs zcompdump zcompdump_ctime zcompdump_fpath zcompdump_mtime zcompdump_tmp zcompinit_refresh zcompstat

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^x^e' edit-command-line

if [[ -t 0 ]]; then
	stty -ixon 2>/dev/null || true
fi

HISTSIZE=10000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --color=always --icons=always $realpath'

(( $+commands[zoxide] )) && eval "$(zoxide init --cmd cd zsh)"
(( $+commands[fzf] )) && eval "$(fzf --zsh)"
(( $+commands[direnv] )) && eval "$(direnv hook zsh)"

alias ll="eza -alh --icons=auto --color=always"
alias s="fastfetch"
alias l="lazygit"
alias m="macmon"
alias tn="tmux new -s"
unalias ta 2>/dev/null || true
function ta {
	local query="${1:-}"
	if (( $# )); then
		shift
	fi
	if [[ -z "$query" ]]; then
		tmux attach "$@"
		return $?
	fi
	if [[ "$query" == -* ]]; then
		tmux attach "$query" "$@"
		return $?
	fi

	local target=""
	local sessions
	sessions="$(tmux list-sessions -F '#{session_id}:::#{session_name}' 2>/dev/null)"

	if [[ -n "$sessions" ]]; then
		if [[ "$query" =~ ^[0-9]+$ ]]; then
			target="$(printf '%s\n' "$sessions" | awk -F ':::' -v idx="$query" '$2 ~ "^"idx"-" {print $1; exit}')"
		else
			target="$(printf '%s\n' "$sessions" | awk -F ':::' -v name="$query" '$2 == name {print $1; exit}')"
			if [[ -z "$target" ]]; then
				target="$(printf '%s\n' "$sessions" | awk -F ':::' -v label="$query" '{name=$2; sub(/^[0-9]+-/, "", name); if (name == label) {print $1; exit}}')"
			fi
		fi
	fi

	if [[ -n "$target" ]]; then
		tmux attach -t "$target" "$@"
		return $?
	fi

	tmux attach -t "$query" "$@"
}
alias tls="tmux ls"
alias c="claude"
alias codex="codex --dangerously-bypass-approvals-and-sandbox"
alias cat="bat"

# Suffix Aliases - Open Files by Extension
# Just type the filename to open it with the associated program
alias -s md='$EDITOR'
alias -s txt=bat
alias -s log=bat
alias -s py='$EDITOR'
alias -s html=open  # macOS: open in default browser

# Hotkey Insertions - Text Snippets
# Insert git commit template (Ctrl+x, g, c)
# \C-b moves cursor back one position
bindkey -s '^xgc' 'git commit -m ""\C-b'

# Yazi setup
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

# Environment variables
export EDITOR="nvim" # For Yazi default editor
path=("$HOME/.local/bin" $path)

# Node Version Manager
export NVM_DIR="$HOME/.nvm"
if [[ -r "$NVM_DIR/alias/default" ]]; then
	nvm_default_version="$(<"$NVM_DIR/alias/default")"
	if [[ -x "$NVM_DIR/versions/node/$nvm_default_version/bin/node" ]]; then
		path=("$NVM_DIR/versions/node/$nvm_default_version/bin" $path)
	fi
	unset nvm_default_version
fi

_load_nvm() {
	unfunction nvm
	[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
	[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
}

nvm() {
	_load_nvm
	nvm "$@"
}

# Cargo (Rust package manager)
[[ -r "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
