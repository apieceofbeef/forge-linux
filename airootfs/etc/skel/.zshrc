# ~/.zshrc -- FORGE Linux default zsh configuration
#
# This file is sourced for interactive zsh shells.  Keep it idempotent.

# Exit early for non-interactive shells (cuts down ssh-scp / rsync noise).
[[ $- == *i* ]] || return

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
typeset -U path PATH
path=(
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
    "$HOME/.local/share/cargo/bin"
    "$HOME/go/bin"
    "$HOME/.bun/bin"
    "$HOME/.deno/bin"
    "$HOME/.npm-global/bin"
    "/usr/local/bin"
    $path
)
export PATH

# -----------------------------------------------------------------------------
# XDG base dirs
# -----------------------------------------------------------------------------
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

# -----------------------------------------------------------------------------
# History
# -----------------------------------------------------------------------------
HISTFILE="$XDG_STATE_HOME/zsh/history"
mkdir -p "${HISTFILE:h}"
HISTSIZE=200000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY
setopt HIST_EXPIRE_DUPS_FIRST
setopt SHARE_HISTORY
setopt EXTENDED_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY_TIME

# -----------------------------------------------------------------------------
# Misc shell options
# -----------------------------------------------------------------------------
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
setopt EXTENDED_GLOB
setopt GLOB_DOTS
setopt NUMERIC_GLOB_SORT
setopt INTERACTIVE_COMMENTS
setopt NO_BEEP
setopt PROMPT_SUBST
setopt LONG_LIST_JOBS
setopt NO_FLOW_CONTROL

# -----------------------------------------------------------------------------
# Editor / pager
# -----------------------------------------------------------------------------
export EDITOR="hx"
export VISUAL="hx"
export PAGER="less"
export LESS="-R --mouse --wheel-lines=3 -F -X"
export MANPAGER="sh -c 'col -bx | bat -l man -p --paging=always'"
export MANROFFOPT="-c"
export SYSTEMD_PAGER=""

# -----------------------------------------------------------------------------
# Completion
# -----------------------------------------------------------------------------
fpath=("$HOME/.local/share/zsh/site-functions" /usr/share/zsh/site-functions $fpath)
autoload -Uz compinit
ZSH_COMPDUMP="$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION"
mkdir -p "${ZSH_COMPDUMP:h}"
# Re-cache once every 24h instead of on every shell start.
if [[ -n $ZSH_COMPDUMP(#qN.mh+24) ]]; then
    compinit -d "$ZSH_COMPDUMP"
else
    compinit -C -d "$ZSH_COMPDUMP"
fi

zstyle ':completion:*'                       use-cache true
zstyle ':completion:*'                       cache-path "$XDG_CACHE_HOME/zsh"
zstyle ':completion:*'                       menu select
zstyle ':completion:*'                       matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*'                       group-name ''
zstyle ':completion:*'                       verbose true
zstyle ':completion:*:descriptions'          format '%F{yellow}-- %d --%f'
zstyle ':completion:*:warnings'              format '%F{red}-- no matches --%f'
zstyle ':completion:*:default'               list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:*:kill:*:processes'    list-colors '=(#b) #([0-9]#)*=0=01;31'

# -----------------------------------------------------------------------------
# Plugins (zsh-syntax-highlighting + zsh-autosuggestions)
# -----------------------------------------------------------------------------
for plugin in \
    /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
    /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
    /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh \
    /usr/share/zsh-history-substring-search/zsh-history-substring-search.zsh
do
    [[ -r "$plugin" ]] && source "$plugin"
done

# syntax-highlighting MUST be sourced last among the highlighters.
for plugin in \
    /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
    /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
do
    [[ -r "$plugin" ]] && source "$plugin"
done

ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_USE_ASYNC=1
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#475569,italic"

# History substring search keys
bindkey '^[[A'  history-substring-search-up
bindkey '^[[B'  history-substring-search-down
bindkey '^P'    history-substring-search-up
bindkey '^N'    history-substring-search-down
bindkey '^[OA'  history-substring-search-up
bindkey '^[OB'  history-substring-search-down

# Sensible Emacs-style line editing with a few Vim conveniences.
bindkey -e
bindkey '^[[1;5C'   forward-word
bindkey '^[[1;5D'   backward-word
bindkey '^[[3~'     delete-char
bindkey '^[[H'      beginning-of-line
bindkey '^[[F'      end-of-line
bindkey '^?'        backward-delete-char

# -----------------------------------------------------------------------------
# FZF integration (Forge-themed)
# -----------------------------------------------------------------------------
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='
  --layout=reverse
  --height=70%
  --border=rounded
  --prompt=" ❯ "
  --pointer="▶"
  --marker="✓"
  --info=inline
  --tabstop=4
  --bind="ctrl-d:half-page-down,ctrl-u:half-page-up,ctrl-/:toggle-preview,ctrl-y:execute-silent(echo {} | wl-copy)"
  --color=fg:#e8e6df,bg:-1,hl:#f59e0b
  --color=fg+:#ffffff,bg+:#15171b,hl+:#fbbf24
  --color=info:#22c55e,prompt:#f59e0b,pointer:#f59e0b
  --color=marker:#22c55e,spinner:#f59e0b,header:#94a3b8
  --color=border:#f59e0b,label:#f59e0b
'
[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -r /usr/share/fzf/completion.zsh  ]] && source /usr/share/fzf/completion.zsh

# -----------------------------------------------------------------------------
# zoxide / mise / starship
# -----------------------------------------------------------------------------
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh --cmd cd)"
fi

if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh)"
    export MISE_EXPERIMENTAL=1
fi

if command -v starship >/dev/null 2>&1; then
    export STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship.toml"
    eval "$(starship init zsh)"
fi

# -----------------------------------------------------------------------------
# bat / eza colours
# -----------------------------------------------------------------------------
export BAT_THEME="ansi"
export BAT_STYLE="numbers,changes,header"
export EZA_COLORS="da=38;5;249:di=38;5;208:ex=38;5;46:ln=38;5;39:un=38;5;160"
export EZA_ICONS_AUTO=1

# -----------------------------------------------------------------------------
# Aliases
# -----------------------------------------------------------------------------
# Coreutils replacements
alias ls='eza --group-directories-first --icons'
alias l='eza -lh --git --group-directories-first --icons'
alias ll='eza -lah --git --group-directories-first --icons --time-style=long-iso'
alias la='eza -a --group-directories-first --icons'
alias lt='eza --tree --level=2 --icons --group-directories-first'
alias tree='eza --tree --icons --group-directories-first'

alias cat='bat --paging=never'
alias less='bat --paging=always'
alias grep='rg --color=auto'
alias find='fd'

alias top='btop'
alias htop='btop'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ps='ps -ef'
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias mkdir='mkdir -pv'

alias vi='hx'
alias vim='hx'
alias nano='hx'
alias e='hx'

# Git
alias g='git'
alias gs='git status --short --branch'
alias gst='git status'
alias gd='git diff'
alias gds='git diff --staged'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gcm='git commit -m'
alias gca='git commit --amend --no-edit'
alias gcan='git commit --amend'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpl='git pull --rebase --autostash'
alias gf='git fetch --all --prune --tags'
alias gl='git log --oneline --graph --decorate --all -n 20'
alias glL='git log --oneline --graph --decorate --all'
alias gb='git branch'
alias gba='git branch -a'
alias gsw='git switch'
alias gswc='git switch -c'
alias grb='git rebase'
alias grbi='git rebase -i'
alias grbc='git rebase --continue'
alias grba='git rebase --abort'
alias gst!='git stash --include-untracked'
alias gsp='git stash pop'
alias glo='lazygit'
alias gg='lazygit'

# Docker
alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
alias dpsa='docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"'
alias dimg='docker images'
alias dexec='docker exec -it'
alias dlogs='docker logs -f --tail 200'
alias dstop='docker stop $(docker ps -q)'
alias dprune='docker system prune -af --volumes'

# Forge
alias forge='fuse'
alias fi='fuse install'
alias fr='fuse remove'
alias fu='fuse update'
alias fU='fuse upgrade'
alias fs='fuse search'
alias fL='fuse list'

# System
alias reload='exec zsh -l'
alias mkpath='export PATH=$PATH:$PWD'
alias cls='clear && printf "\033[3J"'
alias path='print -l $path'

# Networking
alias ip='ip --color=auto'
alias ports='ss -tulpn'
alias myip='curl -fsSL https://ifconfig.me; echo'
alias localip='ip -4 -j addr show scope global | jq -r ".[].addr_info[].local"'

# Quick navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# Pacman / yay shortcuts (still useful even with fuse)
alias yeet='sudo pacman -Rns'

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
mkcd() {
    [[ $# -eq 1 ]] || { print -u2 "usage: mkcd <dir>"; return 1; }
    mkdir -pv -- "$1" && cd -- "$1"
}

# Universal archive extractor.
extract() {
    local file
    if (( $# == 0 )); then
        print -u2 "usage: extract <archive> [archive ...]"
        return 1
    fi
    for file in "$@"; do
        if [[ ! -f $file ]]; then
            print -u2 "extract: $file: not a regular file"
            continue
        fi
        case "$file" in
            *.tar.bz2|*.tbz2)   tar -xvjf -- "$file" ;;
            *.tar.gz|*.tgz)     tar -xvzf -- "$file" ;;
            *.tar.xz|*.txz)     tar -xvJf -- "$file" ;;
            *.tar.zst|*.tzst)   tar --zstd -xvf -- "$file" ;;
            *.tar)              tar -xvf  -- "$file" ;;
            *.bz2)              bunzip2     -- "$file" ;;
            *.gz)               gunzip      -- "$file" ;;
            *.xz)               unxz        -- "$file" ;;
            *.zst)              unzstd      -- "$file" ;;
            *.zip|*.jar|*.war)  unzip       -- "$file" ;;
            *.7z)               7z x        -- "$file" ;;
            *.rar)              unrar x     -- "$file" ;;
            *.lz4)              lz4 -d      -- "$file" ;;
            *.Z)                uncompress  -- "$file" ;;
            *.deb)              ar x        -- "$file" ;;
            *.cpio)             cpio -idmv  < "$file" ;;
            *)
                print -u2 "extract: don't know how to extract '$file'"
                return 1
                ;;
        esac
    done
}

# new-project <kind> <name>
new-project() {
    if (( $# < 2 )); then
        cat <<EOF
usage: new-project <rust|node|go|python> <name>

  rust    -> cargo new --bin
  node    -> npm init -y + minimal scaffold
  go      -> go mod init github.com/$(whoami)/<name>
  python  -> uv-style venv + pyproject.toml + src/<name>/
EOF
        return 1
    fi

    local kind="$1" name="$2"
    if [[ -e $name ]]; then
        print -u2 "new-project: '$name' already exists"
        return 1
    fi

    case "$kind" in
        rust)
            cargo new --bin "$name" || return 1
            ;;
        node)
            mkdir -p "$name/src" && cd "$name" || return 1
            npm init -y >/dev/null
            cat > src/index.js <<'EOF'
console.log("Hello, FORGE!");
EOF
            cat > .gitignore <<'EOF'
node_modules/
dist/
.env
EOF
            ;;
        go)
            mkdir -p "$name" && cd "$name" || return 1
            go mod init "github.com/$(whoami)/$name"
            cat > main.go <<'EOF'
package main

import "fmt"

func main() {
    fmt.Println("Hello, FORGE!")
}
EOF
            ;;
        python)
            mkdir -p "$name/src/$name" "$name/tests" && cd "$name" || return 1
            python -m venv .venv
            cat > pyproject.toml <<EOF
[project]
name = "$name"
version = "0.1.0"
description = ""
requires-python = ">=3.11"
dependencies = []

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
EOF
            cat > "src/$name/__init__.py" <<EOF
def main() -> None:
    print("Hello, FORGE!")
EOF
            cat > .gitignore <<'EOF'
.venv/
__pycache__/
*.egg-info/
dist/
build/
.env
EOF
            ;;
        *)
            print -u2 "new-project: unknown kind '$kind'"
            return 1
            ;;
    esac

    git init -q && git add -A && git -c user.email=forge@localhost -c user.name=forge commit -qm "Initial commit" || true
    print -P "%F{green}✓%f Created $kind project '$name'"
}

# fkill -- fuzzy kill a process
fkill() {
    local pid
    pid=$(ps -ef | sed 1d | fzf --multi --header='Select process to kill' | awk '{print $2}') || return
    [[ -z $pid ]] && return
    local sig="${1:-15}"
    print -P "%F{yellow}killing%f $pid with -$sig"
    kill "-$sig" $pid
}

# Show what's listening on a port: ports-of 8080
ports-of() {
    [[ -z $1 ]] && { print -u2 "usage: ports-of <port>"; return 1; }
    ss -tulpnH "sport = :$1"
}

# Convenience: edit a command in $EDITOR before running it.
autoload -Uz edit-command-line && zle -N edit-command-line && bindkey '^X^E' edit-command-line

# -----------------------------------------------------------------------------
# Greeting (fastfetch on the first interactive shell of a tty)
# -----------------------------------------------------------------------------
__forge_greet() {
    local stamp_dir="$XDG_RUNTIME_DIR"
    [[ -z $stamp_dir ]] && stamp_dir="$XDG_CACHE_HOME"
    local stamp="$stamp_dir/forge-greet-${TTY##*/}.stamp"

    [[ -e $stamp ]] && return
    : > "$stamp"

    if command -v fastfetch >/dev/null 2>&1; then
        fastfetch --config "${XDG_CONFIG_HOME}/fastfetch/config.jsonc" 2>/dev/null \
            || fastfetch --config /etc/forge/fastfetch.jsonc 2>/dev/null \
            || fastfetch
    elif [[ -r /etc/forge/logo.txt ]]; then
        cat /etc/forge/logo.txt
    fi
}
__forge_greet

# -----------------------------------------------------------------------------
# Per-host / per-user overrides
# -----------------------------------------------------------------------------
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
