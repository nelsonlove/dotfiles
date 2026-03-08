# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

source "${XDG_CONFIG_HOME}/zsh/includes.zsh"

export ZSH="${XDG_DATA_HOME}/.oh-my-zsh"

plugins=(
    brew
    colored-man-pages
    common-aliases
    copybuffer
    copypath
    direnv
    docker
    extract
    gh
    git
    gitfast
    gnu-utils
    history
    macos
    magic-enter
    npm
    pip
    python
    safe-paste
    sudo
    tmux
    web-search
    z
    zsh-syntax-highlighting  # must be last
)

ZSH_THEME="powerlevel10k/powerlevel10k"
export POWERLEVEL9K_CONFIG_FILE="${XDG_CONFIG_HOME}/zsh/p10k.zsh"

## magic-enter
export MAGIC_ENTER_GIT_COMMAND='ls -a && echo && gst -u .'

## tmux
export ZSH_TMUX_CONFIG="${XDG_CONFIG_HOME}/tmux/tmux.conf"
export ZSH_TMUX_AUTOQUIT=false

if [[ -z "$TMUX" && -z "$INSIDE_EMACS" && -z "$SSH_CONNECTION" ]]; then
    export ZSH_TMUX_AUTOSTART=true
else
    export ZSH_TMUX_AUTOSTART=false
fi

# Initialize Oh My Zsh
source "${ZSH}/oh-my-zsh.sh"

# Aliases
alias emacsclient="/Applications/Emacs.app/Contents/MacOS/bin/emacsclient"
function ec {
  local flags=() args=()
  for a in "$@"; do
    if [[ "$a" = -* ]]; then flags+=("$a")
    elif [[ "$a" = /* ]]; then args+=("$a")
    else args+=("$PWD/$a")
    fi
  done
  [[ ${#args[@]} -eq 0 ]] && args+=("$PWD")
  command emacsclient "${flags[@]}" "${args[@]}"
}
alias ecg="ec -c"        # open in GUI frame
alias ect="ec -nw"       # open in terminal
export EDITOR="/Applications/Emacs.app/Contents/MacOS/bin/emacsclient"
alias gcon="git -c core.hooksPath=/dev/null checkout"
alias karabiner="/Library/Application\ Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
alias pxi='pipx install'
alias pxr='pipx run'
alias pxl='pipx list'
alias pxu='pipx upgrade'
alias pxun='pipx uninstall'
alias pxe='pipx environment'
alias claude-safe="claude"
alias claude="claude --dangerously-skip-permissions"
alias claude-remote="claude remote-control"

# Functions
function vrun() {
    local name="${1:-.venv}"
    local venvpath="${name:P}"
    if [[ ! -d "$venvpath" ]]; then
        echo >&2 "Error: no such venv in current directory: $name"
        return 1
    fi
    if [[ ! -f "${venvpath}/bin/activate" ]]; then
        echo >&2 "Error: '${name}' is not a proper virtual environment"
        return 1
    fi
    . "${venvpath}/bin/activate" || return $?
    echo "Activated virtual environment ${name}"
}

# Emacs vterm integration (only inside vterm)
if [[ "$INSIDE_EMACS" = 'vterm' ]]; then
    source "${XDG_CONFIG_HOME}/zsh/emacs.zsh"
fi

# Python
if command -v brew >/dev/null 2>&1; then
    export PATH="$(brew --prefix python)/libexec/bin:${PATH}"
fi
eval "$(register-python-argcomplete pipx)"

# Local overrides
touch_and_execute "${XDG_CONFIG_HOME}/zsh/zshrc.local"

# Powerlevel10k config
[[ ! -f $POWERLEVEL9K_CONFIG_FILE ]] || source "$POWERLEVEL9K_CONFIG_FILE"

# jd-cli wrapper
jd() {
  if [[ "$1" == "cd" ]]; then
    shift
    local target
    target=$(command jd cd "$@")
    if [[ $? -eq 0 && -n "$target" ]]; then
      builtin cd "$target"
    fi
  else
    command jd "$@"
  fi
}

# Completions
# source "$HOME/.openclaw/completions/openclaw.zsh"
fpath=(~/.zfunc ~/.zsh/completions $fpath)
autoload -Uz compinit && compinit

# Bun
# export PATH="$HOME/.bun/bin:$PATH"
