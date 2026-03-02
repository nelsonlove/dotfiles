#!/bin/bash
set -euo pipefail

# Bootstrap a fresh macOS machine.
# Installs Nix + Homebrew, clones dotfiles, runs first darwin-rebuild.

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

# 3. Clone dotfiles
if [ ! -d "$DOTFILES" ]; then
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
