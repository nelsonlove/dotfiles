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

# Source secrets from iCloud
source "${HOME}/Documents/00-09 Meta/06 Digital tools/06.04 Secrets/zsh/env.zsh"

touch_and_execute "$XDG_CONFIG_HOME/zsh/zprofile.local"
