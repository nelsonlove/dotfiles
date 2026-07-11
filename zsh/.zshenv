# Sourced first for every zsh invocation, before .zprofile/.zshrc.
# Point ZDOTDIR at the XDG config dir so the real startup files live in
# ~/.config/zsh (symlinked to this repo) instead of $HOME. This file is the
# one zsh dotfile that must sit in $HOME (symlinked to ~/.zshenv); zsh reads
# it while ZDOTDIR still defaults to $HOME, then honors the override for the
# remaining startup files.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export ZDOTDIR="${XDG_CONFIG_HOME}/zsh"

# Canonical locations, declared once — everything downstream (zprofile,
# includes.zsh, scripts) derives from these instead of hardcoding paths.
export DOTFILES="${HOME}/repos/dotfiles"
export SECRETS_DIR="${HOME}/Documents/00-09 System/09 Secrets & credentials/09.11 Secrets"

# Machine-specific env & secrets — gitignored (zsh/*.local). Sourced after the
# defaults so a machine can override DOTFILES/SECRETS_DIR or preset tokens.
[[ -f "${ZDOTDIR}/zshenv.local" ]] && source "${ZDOTDIR}/zshenv.local"

# GitHub token — from the gh keyring, no plaintext secret stored. Guarded so
# nested shells (and a zshenv.local that set it) don't re-run gh, and the var
# stays unset (not exported-empty) when gh is missing or logged out.
if [[ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]] && command -v gh >/dev/null 2>&1; then
    _ghtoken="$(gh auth token 2>/dev/null)"
    [[ -n "$_ghtoken" ]] && export GITHUB_PERSONAL_ACCESS_TOKEN="$_ghtoken"
    unset _ghtoken
fi
