source "${HOME}/.config/zsh/includes.zsh"

if [[ "$(system_type)" == "darwin" ]]; then
    init_brew
    export PATH="$(brew --prefix gnu-getopt)/libexec/gnubin:$PATH"
    export PATH="$(brew --prefix gnu-tar)/libexec/gnubin:$PATH"
    export PATH="$(brew --prefix gnu-sed)/libexec/gnubin:$PATH"
    export PATH="$(brew --prefix grep)/libexec/gnubin:$PATH"
    export SSL_CERT_FILE="$(brew --prefix)/etc/ca-certificates/cert.pem"
fi

export NODE_EXTRA_CA_CERTS="${SSL_CERT_FILE}"

if [[ -d "${HOME}/bin" ]]; then
    export PATH="${HOME}/bin:${PATH}"
fi

if [[ -d "${HOME}/.local/bin" ]]; then
    export PATH="${HOME}/.local/bin:${PATH}"
fi

# Emacs (emacs-mac port) — only when installed
[[ -d "/Applications/Emacs.app/Contents/MacOS/bin" ]] && \
    export PATH="/Applications/Emacs.app/Contents/MacOS/bin:$PATH"

# Source secrets from iCloud (skip if the vault isn't synced on this machine)
_secrets="${HOME}/Documents/00-09 System/05 Secrets & credentials/05.11 Secrets/zsh/env.zsh"
[[ -f "$_secrets" ]] && source "$_secrets"
unset _secrets

# GitHub (dynamic — uses keychain token via gh CLI, if authed)
command -v gh >/dev/null 2>&1 && \
    export GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token 2>/dev/null)"

touch_and_execute "$XDG_CONFIG_HOME/zsh/zprofile.local"
