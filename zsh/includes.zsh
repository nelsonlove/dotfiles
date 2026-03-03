export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_LOCAL_HOME="${HOME}/.local"
export XDG_DATA_HOME="${XDG_LOCAL_HOME}/share"


touch_and_execute() {
    local -r filepath="${1}"
    if [[ ! -f "${filepath}" ]]; then
        touch "${filepath}"
    fi
    source "${filepath}"
}


system_type() {
    if [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif uname -a | grep -q "Darwin"; then
        echo "darwin"
    else
        echo "unknown"
    fi
}


init_brew() {
    local -r _os="$(system_type)"
    if [[ "${_os}" != "darwin" ]]; then
        return
    elif command -v brew >/dev/null 2>&1; then
        return
    elif [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}
