#!/bin/bash
set -euo pipefail

# Bootstrap a fresh macOS machine.
# Installs Nix + Homebrew, clones dotfiles, runs darwin-rebuild switch.
#
# Usage:
#   curl -O https://raw.githubusercontent.com/nelsonlove/dotfiles/main/install/bootstrap.sh
#   bash bootstrap.sh

REPO="git@github.com:nelsonlove/dotfiles.git"
DOTFILES="$HOME/repos/dotfiles"
HOSTNAME=$(scutil --get LocalHostName)

echo "==> Bootstrapping $HOSTNAME"

# 1. Install Nix (Determinate Systems — flakes enabled out of the box)
if ! command -v nix &>/dev/null; then
  echo "==> Installing Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L \
    https://install.determinate.systems/nix | sh -s -- install
  echo "==> Nix installed. Restart your shell, then rerun this script."
  exit 0
fi

# 2. Install Homebrew
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# 3. Clone dotfiles (requires SSH key or gh auth)
if [ ! -d "$DOTFILES" ]; then
  if ! ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "==> GitHub SSH auth required. Either:"
    echo "      1. Add an SSH key:  ssh-keygen && cat ~/.ssh/id_ed25519.pub"
    echo "      2. Use gh CLI:      brew install gh && gh auth login"
    echo "    Then rerun this script."
    exit 1
  fi
  echo "==> Cloning dotfiles..."
  mkdir -p "$HOME/repos"
  git clone "$REPO" "$DOTFILES"
fi

# 4. First nix-darwin build
echo "==> Running darwin-rebuild switch for $HOSTNAME..."
cd "$DOTFILES"
if command -v darwin-rebuild &>/dev/null; then
  darwin-rebuild switch --flake ".#$HOSTNAME"
else
  nix run nix-darwin -- switch --flake ".#$HOSTNAME"
fi

echo "==> Done. System is configured."
