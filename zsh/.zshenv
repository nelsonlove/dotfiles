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
#
# DOTFILES is derived from this file instead of hardcoded: %x is the path of the
# file currently being sourced (~/.zshenv), :A resolves that symlink back into
# the repo, and :h:h climbs zsh/ -> repo root. Moving the repo therefore needs
# no edit here — re-running `install/install.sh --only links` is enough. The
# literal fallback only covers a zsh that reports no %x, or a ~/.zshenv that is
# a real file rather than the symlink install.sh creates.
DOTFILES="${${(%):-%x}:A:h:h}"
[[ -f "${DOTFILES}/install/manifest.yaml" ]] || DOTFILES="${HOME}/repos/system/dotfiles"
export DOTFILES
export SECRETS_DIR="${HOME}/Documents/00-09 System/09 Secrets & credentials/09.11 Secrets"

# Tickle reads jobs/scripts from dotfiles (versioned, mirrored across machines);
# runtime state (runs/state/logs/bin) stays per-machine in the default DATA_HOME.
# Must match the daemon plist's TICKLE_CONFIG_HOME (install/launchagents/dev.tickle.daemon.plist),
# which is a plain string with no expansion — move the repo and that plist needs
# a matching edit plus `install/install.sh --only launchagents`.
export TICKLE_CONFIG_HOME="${DOTFILES}/tickle"

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
