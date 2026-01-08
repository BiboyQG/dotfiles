# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

if [ ! -d "$ZINIT_HOME" ]; then
	mkdir -p "$(dirname $ZINIT_HOME)"
	git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

source "${ZINIT_HOME}/zinit.zsh"

zinit ice depth=1; zinit light romkatv/powerlevel10k

zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

zinit snippet OMZP::git
zinit snippet OMZP::kubectl
zinit snippet OMZP::kubectx
zinit snippet OMZP::command-not-found

autoload -U compinit && compinit

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

bindkey '$' autosuggest-accept
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward

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
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'

eval "$(zoxide init --cmd cd zsh)"

eval "$(fzf --zsh)"

eval "$(direnv hook zsh)"

alias ll="eza -alh --icons=automatic"
alias ssh="kitten ssh"
alias s="fastfetch"
alias l="lazygit"
alias m="macmon"
alias tn="tmux new -s"
unalias ta 2>/dev/null || true
function ta {
	local query="${1:-}"
	shift || true
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

# The following lines have been added by Docker Desktop to enable Docker CLI completions.
fpath=(/Users/biboy/.docker/completions $fpath)
autoload -Uz compinit
compinit
# End of Docker CLI completions

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

# Node Version Manager
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
