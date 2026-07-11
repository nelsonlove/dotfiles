# Sourced first for every zsh invocation, before .zprofile/.zshrc.
# Point ZDOTDIR at the XDG config dir so the real startup files live in
# ~/.config/zsh (symlinked to this repo) instead of $HOME. This file is the
# one zsh dotfile that must sit in $HOME (symlinked to ~/.zshenv); zsh reads
# it while ZDOTDIR still defaults to $HOME, then honors the override for the
# remaining startup files.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export ZDOTDIR="${XDG_CONFIG_HOME}/zsh"

# GitHub MCP token — sourced from gh keyring, no plaintext secret stored
export GITHUB_PERSONAL_ACCESS_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN:-$(command -v gh >/dev/null 2>&1 && gh auth token 2>/dev/null)}"
