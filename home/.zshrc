typeset -U path PATH
unset NO_COLOR

# Apply direnv's environment before the instant prompt. Its precmd hook prints
# "direnv: loading ..." otherwise, which trips the p10k warning about console
# output during initialization.
(( $+commands[direnv] )) && emulate zsh -c "$(direnv export zsh)"

# The instant prompt points stdin at /dev/null until the first prompt, so
# below it `[[ -t 0 ]]` is false and flow control would stay on.
[[ -t 0 ]] && stty -ixon

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
typeset -U fpath FPATH
fpath=(/opt/homebrew/share/zsh/site-functions $fpath)
# brew shellenv, for example from ~/.zprofile.local, exports FPATH; a child
# shell (a tmux pane) would then build fpath in a different order and rebuild
# the compinit dump on every start.
typeset +x FPATH

if [[ -r "$ZINIT_HOME/zinit.zsh" ]]; then
	source "$ZINIT_HOME/zinit.zsh"

	# zsh-syntax-highlighting wraps no widgets on zsh 5.9, so the rebind that
	# autosuggestions otherwise repeats before every prompt does nothing.
	ZSH_AUTOSUGGEST_MANUAL_REBIND=1
	# The for-syntax keeps light mode, which skips zinit's per-plugin
	# function, parameter and option diff tracking.
	zinit light-mode depth=1 for \
		romkatv/powerlevel10k \
		zsh-users/zsh-syntax-highlighting \
		zsh-users/zsh-completions \
		zsh-users/zsh-autosuggestions \
		Aloxaf/fzf-tab
	# OMZP::git forks `git version` on load; defer both snippets past the
	# first prompt. setup.sh runs `@zinit-scheduler burst` to load them.
	zinit wait lucid for OMZL::git.zsh OMZP::git
else
	print -u2 "zinit is not installed; rerun the dotfiles setup script"
fi

if [[ -d "$HOME/.docker/completions" ]]; then
	fpath=("$HOME/.docker/completions" $fpath)
fi

autoload -Uz compinit
zmodload -F zsh/stat b:zstat
zcompdump="${ZDOTDIR:-$HOME}/.zcompdump-${ZSH_VERSION}"
zcompdump_fpath="${zcompdump}.fpath"
# Rebuild (and rerun compaudit) only when the completion directory set or
# one of those directories changes; the dump stays valid otherwise.
typeset -Ua zcompdirs=( ${^fpath}(N-/) )
typeset -a zcompstat
zcompinit_refresh=0
zcomp_signature="${(F)zcompdirs}"
if [[ ! -f "$zcompdump" ]] \
	|| [[ ! -f "$zcompdump_fpath" ]] \
	|| [[ "$(<"$zcompdump_fpath")" != "$zcomp_signature" ]] \
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
	# compinit reuses an existing dump whose file count still matches.
	rm -f -- "$zcompdump"
	compinit -d "$zcompdump"
	print -r -- "$zcomp_signature" >| "$zcompdump_fpath"
else
	compinit -C -d "$zcompdump"
fi
unset zcomp_signature zcompctime zcompdirs zcompdump zcompdump_ctime zcompdump_fpath zcompinit_refresh zcompstat

# Plugins loaded before compinit queue their compdef registrations in Zinit.
if (( $+functions[zinit] )); then
	zinit cdreplay -q
fi

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

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

# Source a tool's cached init script instead of forking the tool on every
# shell start. The cache is keyed on the resolved binary path, which for
# Homebrew contains the Cellar version; bottle mtimes do not change on upgrade.
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
(( $+commands[zoxide] )) && _cached_init zoxide init --cmd cd zsh
(( $+commands[fzf] )) && _cached_init fzf --zsh
(( $+commands[direnv] )) && _cached_init direnv hook zsh

alias ll="eza -alh --icons=auto --color=always"
alias s="fastfetch"
alias l="lazygit"
alias tn="tmux new -s"
function ta {
	if [[ -z "${1:-}" || "$1" == -* ]]; then
		tmux attach "$@"
		return
	fi
	local query="$1"
	shift

	# tmux refuses to attach from inside a session; switch the client instead.
	# switch-client takes none of attach's options, so trailing flags are
	# rejected there instead of being passed through.
	local cmd=attach
	if [[ -n "${TMUX:-}" ]]; then
		cmd=switch-client
		if (( $# )); then
			print -u2 "ta: attach options are not supported inside tmux: $*"
			return 2
		fi
	fi
	local target sessions
	sessions="$(tmux list-sessions -F '#{session_id}:::#{session_name}' 2>/dev/null)"
	if [[ "$query" =~ ^[0-9]+$ ]]; then
		target="$(printf '%s\n' "$sessions" | awk -F ':::' -v idx="$query" '$2 ~ "^"idx"-" {print $1; exit}')"
	else
		target="$(printf '%s\n' "$sessions" | awk -F ':::' -v name="$query" '$2 == name {print $1; exit}')"
		if [[ -z "$target" ]]; then
			target="$(printf '%s\n' "$sessions" | awk -F ':::' -v label="$query" '{name=$2; sub(/^[0-9]+-/, "", name); if (name == label) {print $1; exit}}')"
		fi
	fi
	tmux "$cmd" -t "${target:-$query}" "$@"
}
alias tls="tmux ls"
alias c="claude"
alias codex="codex --dangerously-bypass-approvals-and-sandbox"
alias cat="bat"

alias -s md='$EDITOR'
alias -s txt=bat
alias -s log=bat
alias -s py='$EDITOR'
alias -s html=open

# \C-b puts the cursor between the quotes.
bindkey -s '^xgc' 'git commit -m ""\C-b'

function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

export EDITOR="nvim"

# Node Version Manager
export NVM_DIR="$HOME/.nvm"
if [[ -r "$NVM_DIR/alias/default" ]]; then
	nvm_default_version="$(<"$NVM_DIR/alias/default")"
	if [[ ! -x "$NVM_DIR/versions/node/$nvm_default_version/bin/node" && -s "$NVM_DIR/nvm.sh" ]]; then
		# Resolve symbolic/partial aliases with NVM itself without loading its
		# functions or completions into the interactive shell.
		nvm_default_version="$(
			source "$NVM_DIR/nvm.sh" --no-use
			nvm version default
		)"
	fi
	if [[ -x "$NVM_DIR/versions/node/$nvm_default_version/bin/node" ]]; then
		path=("$NVM_DIR/versions/node/$nvm_default_version/bin" $path)
	fi
	unset nvm_default_version
fi

nvm() {
	unfunction nvm
	[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
	[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
	nvm "$@"
}

# Cargo (Rust package manager)
if [[ -r "$HOME/.cargo/env" ]]; then
	source "$HOME/.cargo/env"
fi
