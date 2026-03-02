#!/bin/bash
set -euo pipefail

# Bootstrap a fresh macOS machine.
# Installs Nix + Homebrew, clones dotfiles, runs darwin-rebuild switch.
#
# Usage:
#   curl -O https://raw.githubusercontent.com/nelsonlove/dotfiles/main/install/bootstrap.sh
#   bash bootstrap.sh

REPO="https://github.com/nelsonlove/dotfiles.git"
DOTFILES="$HOME/repos/dotfiles"
HOSTNAME=$(scutil --get LocalHostName)

echo "==> Bootstrapping $HOSTNAME"

# 1. Xcode Command Line Tools (provides git, clang, etc.)
if ! xcode-select -p &>/dev/null; then
  echo "==> Installing Xcode Command Line Tools..."
  xcode-select --install
  echo "==> Follow the prompt to install, then rerun this script."
  exit 0
fi

# 2. Rosetta 2 (for x86 binaries on Apple Silicon)
if [ "$(uname -m)" = "arm64" ] && ! /usr/bin/pgrep -q oahd; then
  echo "==> Installing Rosetta..."
  softwareupdate --install-rosetta --agree-to-license
fi

# 3. Install Nix (Determinate Systems — flakes enabled out of the box)
if ! command -v nix &>/dev/null; then
  echo "==> Installing Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L \
    https://install.determinate.systems/nix | sh -s -- install
  echo "==> Nix installed. Restart your shell, then rerun this script."
  exit 0
fi

# 4. Install Homebrew
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv zsh)"
fi

# 5. Authenticate with GitHub
if ! gh auth status &>/dev/null; then
  echo "==> Authenticating with GitHub..."
  command -v gh &>/dev/null || brew install gh
  gh auth login --web
fi

# 6. Clone dotfiles
if [ ! -d "$DOTFILES" ]; then
  echo "==> Cloning dotfiles..."
  mkdir -p "$HOME/repos"
  git clone "$REPO" "$DOTFILES"
fi

# 7. First nix-darwin build
echo "==> Running darwin-rebuild switch for $HOSTNAME..."
cd "$DOTFILES"
if command -v darwin-rebuild &>/dev/null; then
  sudo darwin-rebuild switch --flake ".#$HOSTNAME"
else
  sudo nix run nix-darwin -- switch --flake ".#$HOSTNAME"
fi

echo "==> Done. System is configured."
