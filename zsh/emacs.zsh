# For reference:
# This plugin utilizes the Emacs daemon capability, allowing the user to quickly open frames, whether they are opened in a terminal via a ssh connection, or X frames opened on the same host. The plugin also provides some aliases for such operations.

# You don't have the cost of starting Emacs all the time anymore
# Opening a file is as fast as Emacs does not have anything else to do.
# You can share opened buffered across opened frames.
# Configuration changes made at runtime are applied to all frames.
#
# Aliases
#
# The plugin uses a custom launcher (which we'll call here $EMACS_LAUNCHER) that
# is just a wrapper around emacsclient.

# Alias
# Command
# Description
#
# emacs
# $EMACS_LAUNCHER --no-wait
# Opens a temporary emacsclient frame
#
# e
# emacs
# Same as emacs alias
#
# te
# $EMACS_LAUNCHER -nw
# Open terminal emacsclient
#
# eeval
# $EMACS_LAUNCHER --eval
# Same as M-x eval but from outside Emacs
#
# eframe
# emacsclient --alternate-editor "" --create-frame
# Create new X frame
#
# efile
# -
# Print the path to the file open in the current buffer
#
# ecd
# -
# Print the directory of the file open in the the current buffer


# fn below duplicates alias in plugin
# e() {
#     osascript -e "tell application \"Emacs.app\" to open \"$(realpath $1)\""
# }

# emacsserver_socket() {
#     lsof -c Emacs | grep "unix.*server" | tr -s " " | cut -d' ' -f8 | head -n 1
# }

# Starts in 24-bit color with this i think?
# emacsclient_alacritty() {
    # # emacsclient -nw --socket-name $(emacsserver_socket) $@
    # TERM=alacritty-direct emacsclient -nw --socket-name $(emacsserver_socket) $@
# }
# alias emacsclient=emacsclient_alacritty

# Alternate configuration for opening emacs outside of emacs -- client/server setup
# See https://emacs.stackexchange.com/a/8089/5444
# Script at dest reads only `emacs -nw -q $@`

# if [[ ${INSIDE_EMACS:-no_emacs_here} = 'no_emacs_here' ]]; then
#     export EDITOR=emacsclient_alacritty
# fi

# Not sure if needed
# alias edit=$EDITOR
# export VISUAL=EDITOR
# export PAGER=less

# Alias for old dotfiles config
# alias config='git --git-dir=$HOME/.cfg/ --work-tree=$HOME"

#######
# Vterm
#######

# Below from https://git.entf.net/dotemacs/file/elpa/vterm-20211226.817/etc/emacs-vterm-zsh.sh.html

# Some of the most useful features in emacs-libvterm require shell-side
# configurations. The main goal of these additional functions is to enable the
# shell to send information to `vterm` via properly escaped sequences. A
# function that helps in this task, `vterm_printf`, is defined below.

function vterm_printf(){
    if [ -n "$TMUX" ] && ([ "${TERM%%-*}" = "tmux" ] || [ "${TERM%%-*}" = "screen" ] ); then
        # Tell tmux to pass the escape sequences through
        printf "\ePtmux;\e\e]%s\007\e\\" "$1"
    elif [ "${TERM%%-*}" = "screen" ]; then
        # GNU screen (screen, screen-256color, screen-256color-bce)
        printf "\eP\e]%s\007\e\\" "$1"
    else
        printf "\e]%s\e\\" "$1"
    fi
}


# With vterm_cmd you can execute Emacs commands directly from the shell.
# For example, vterm_cmd message "HI" will print "HI".
# To enable new commands, you have to customize Emacs's variable
# vterm-eval-cmds.
vterm_cmd() {
    local vterm_elisp
    vterm_elisp=""
    while [ $# -gt 0 ]; do
        vterm_elisp="$vterm_elisp""$(printf '"%s" ' "$(printf "%s" "$1" | sed -e 's|\\|\\\\|g' -e 's|"|\\"|g')")"
        shift
    done
    vterm_printf "51;E$vterm_elisp"
}

# Sync directory and host in the shell with Emacs's current directory.
# You may need to manually specify the hostname instead of $(hostname) in case
# $(hostname) does not return the correct string to connect to the server.
#
# The escape sequence "51;A" has also the role of identifying the end of the
# prompt
vterm_prompt_end() {
    vterm_printf "51;A$(whoami)@$(hostname):$(pwd)";
}


vterm_printenv() {
    tmpfile=$(mktemp /tmp/abc-script.XXXXXX)
    printenv |\
        sed ':a;N;$!ba;s/\n/\t/g' |\
        sed 's/\(\w*\)=\([^\t]*\)/("\1" . "\2")/g' |\
        sed 's/\t/ /g' > $tmpfile
    vterm_cmd vterm-update-env $tmpfile
}

if [[ "$INSIDE_EMACS" = 'vterm' ]]; then
    # Completely clear the buffer. With this, everything that is not on screen
    # is erased.
    alias clear='vterm_printf "51;Evterm-clear-scrollback";tput clear'
    setopt PROMPT_SUBST
    PROMPT=$PROMPT'%{$(vterm_prompt_end)%}'
    # This is to change the title of the buffer based on information provided by the
    # shell. See, http://tldp.org/HOWTO/Xterm-Title-4.html, for the meaning of the
    # various symbols.
    autoload -U add-zsh-hook
    add-zsh-hook -Uz chpwd (){ print -Pn "\e]2;%m:%2~\a" }
    export EDITOR="vterm_cmd find-file-other-window"
    alias magit="vterm_cmd magit-status"
    alias man="vterm_cmd man"
fi
