#!/usr/bin/env bash
# Bootstrap a fresh macOS machine, then hand off to the interactive installer.
#
# The repo is public, so this one-liner works with no auth:
#   curl -fsSL https://raw.githubusercontent.com/nelsonlove/dotfiles/main/install/bootstrap.sh | bash
#
# Steps: Xcode CLT -> Rosetta (Apple Silicon) -> Homebrew -> clone -> install.sh

set -euo pipefail

REPO="https://github.com/nelsonlove/dotfiles.git"
DOTFILES="$HOME/repos/dotfiles"

bold=$'\033[1m'; rst=$'\033[0m'
hdr() { printf "\n%s==> %s%s\n" "$bold" "$*" "$rst"; }

hdr "Bootstrapping $(scutil --get LocalHostName 2>/dev/null || hostname)"

# 1. Xcode Command Line Tools (git, clang, make).
if ! xcode-select -p &>/dev/null; then
  hdr "Installing Xcode Command Line Tools…"
  xcode-select --install
  echo "Finish the GUI install prompt, then re-run this script."
  exit 0
fi

# 2. Rosetta 2 for x86 binaries on Apple Silicon.
if [[ "$(uname -m)" == "arm64" ]] && ! /usr/bin/pgrep -q oahd; then
  hdr "Installing Rosetta 2…"
  softwareupdate --install-rosetta --agree-to-license
fi

# 3. Homebrew.
if ! command -v brew &>/dev/null; then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    hdr "Installing Homebrew…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi

# 4. Clone (or update) the dotfiles repo. Public repo -> plain HTTPS, no gh.
if [[ ! -d "$DOTFILES/.git" ]]; then
  hdr "Cloning dotfiles…"
  mkdir -p "$HOME/repos"
  git clone "$REPO" "$DOTFILES"
else
  hdr "dotfiles already cloned at $DOTFILES"
fi

# 5. Hand off to the interactive installer.
hdr "Launching installer…"
exec "$DOTFILES/install/install.sh" "$@"
