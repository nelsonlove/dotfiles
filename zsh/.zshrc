# Over SSH, take over this Mac's tmux instead of getting a bare shell: if a
# session is running, `attach -d` grabs it *and detaches any other client* (so
# the remote session isn't a mirror of the local screen); if none is running,
# start a fresh one. This MUST run above the p10k instant-prompt block below —
# instant prompt redirects the TTY, after which tmux attach fails with "open
# terminal failed: not a terminal". Not `exec`: a clean detach returns 0 and we
# `exit` to close the SSH session; a tmux failure returns non-zero and we fall
# through to a normal login shell. `command tmux` skips the omz tmux-plugin
# alias; `-z "$TMUX"` avoids nesting.
# Disabled 2026-07-11: no opt-out at connect time — every SSH login seizes the
# session (attach -d yanks it off the local screen) and detach closes the
# connection. Re-enable once it has an escape hatch (e.g. a NOTMUX guard).
# if [[ -n "$SSH_CONNECTION" && -z "$TMUX" ]] && command -v tmux >/dev/null; then
#     if command tmux ls >/dev/null 2>&1; then
#         command tmux attach -d && exit    # existing session: take it over (detach local client)
#     else
#         command tmux new-session && exit  # nothing running: start one
#     fi
# fi

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
)

# Plugins that eval `<tool> init/hook` at load and error if the binary is
# absent. The rc is always symlinked, but zoxide (group:shell) / direnv
# (group:dev) may not be installed (e.g. a core-only install), so add them
# only when present.
command -v zoxide >/dev/null 2>&1 && plugins+=(zoxide)
command -v direnv >/dev/null 2>&1 && plugins+=(direnv)
command -v thefuck >/dev/null 2>&1 && plugins+=(thefuck)  # `fuck` alias + ESC-ESC binding
plugins+=(zsh-syntax-highlighting)  # must be last

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

# Editor — prefer the Emacs (emacs-mac port) emacsclient when installed,
# otherwise fall back to micro. Emacs is not installed by the Brewfile (it's
# built via the nix flow), so guard everything emacs on the binary existing.
EMACSCLIENT="/Applications/Emacs.app/Contents/MacOS/bin/emacsclient"
if [[ -x "$EMACSCLIENT" ]]; then
  alias emacsclient="$EMACSCLIENT"
  function ec {
    local flags=() args=()
    for a in "$@"; do
      if [[ "$a" = -* ]]; then flags+=("$a")
      elif [[ "$a" = /* ]]; then args+=("$a")
      else args+=("$PWD/$a")
      fi
    done
    [[ ${#args[@]} -eq 0 ]] && args+=("$PWD")
    command "$EMACSCLIENT" "${flags[@]}" "${args[@]}"
  }
  alias ecg="ec -c"        # open in GUI frame
  alias ect="ec -nw"       # open in terminal
  export EDITOR="$EMACSCLIENT"
elif command -v micro >/dev/null 2>&1; then
  export EDITOR="micro"
fi
alias gcon="git -c core.hooksPath=/dev/null checkout"
alias karabiner="/Library/Application\ Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
alias pxi='pipx install'
alias pxr='pipx run'
alias pxl='pipx list'
alias pxu='pipx upgrade'
alias pxun='pipx uninstall'
alias pxe='pipx environment'
alias claude-safe="command claude"
alias claude-remote="command claude remote-control"

# Make bare `mv` fail LOUD on collision. oh-my-zsh's common-aliases plugin sets
# `mv='mv -i'`; under `set -e` in a non-interactive shell (e.g. the Claude Code
# Bash tool, which sources this profile) `mv -i src dst` where dst exists hits
# EOF on the prompt, silently SKIPS the move, and exits 0 — hiding bulk-move
# failures (bit us 2026-04, W18 rollup, 2026-06-23 pattern-library flatten).
# GNU coreutils' `--update=none-fail` instead prints "not replacing '<dst>'",
# exits non-zero, and leaves both files untouched. Pin to `gmv` (not `mv`):
# the Bash tool sometimes resolves `mv` to BSD /bin/mv, which has no --update.
# Escape hatch for a DELIBERATE overwrite: `mv --update=all src dst` (last
# --update wins). Note `-f` does NOT override none-fail. Guarded on `gmv` so a
# shell without Homebrew coreutils keeps the default mv rather than erroring.
# Task b9da027f-93eb-424a-b7ad-cdc65dbd18a0.
command -v gmv >/dev/null 2>&1 && alias mv='gmv --update=none-fail'

# Auto-route to jd claude when inside the JD tree
command -v jd >/dev/null 2>&1 && eval "$(jd claude --setup)"

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
command -v register-python-argcomplete >/dev/null 2>&1 && eval "$(register-python-argcomplete pipx)"

# Local overrides
touch_and_execute "${XDG_CONFIG_HOME}/zsh/zshrc.local"

# Powerlevel10k config
[[ ! -f $POWERLEVEL9K_CONFIG_FILE ]] || source "$POWERLEVEL9K_CONFIG_FILE"

# jd-cli shell integration (cd wrapper + completions)
command -v jd >/dev/null 2>&1 && eval "$(jd cd --setup)"

# Completions
fpath=(~/.zfunc ~/.zsh/completions $fpath)
autoload -Uz compinit && compinit

# Bun
# export PATH="$HOME/.bun/bin:$PATH"

# Set up fzf key bindings and fuzzy completion
command -v fzf >/dev/null 2>&1 && source <(fzf --zsh)
