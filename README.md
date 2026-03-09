# Dotfiles

Personal system configuration and bootstrap for macOS.

## Scope

This repo owns:
- **Config files** — shell, editor, terminal, git, tmux
- **Package lists** — Homebrew, pip, npm
- **macOS defaults** — system preferences
- **Install/bootstrap scripts** — the orchestrator for a fresh machine
- **System policy docs** — JD conventions, XDG layout, repo management
- **Manifest** — what repos to clone, where to symlink them

This repo does NOT own:
- The JD CLI (`~/repos/johnnydecimal.py`) — separate repo, pulled in during bootstrap
- Project repos — cloned per the manifest
- The JD tree itself — lives on iCloud Drive, wired up by symlinks

## Bootstrap

```bash
# On a fresh Mac:
curl -fsSL https://raw.githubusercontent.com/nelsonlove/dotfiles/main/install/bootstrap.sh | bash
```

The bootstrap script:
1. Installs Xcode CLI tools + Homebrew
2. Clones this repo to `~/repos/dotfiles`
3. Symlinks configs into `~/.config/`
4. Installs packages (Brewfile, pip, npm)
5. Applies macOS defaults
6. Clones the JD CLI and other repos from the manifest
7. Creates JD symlinks in the Documents tree

## Layout

```
install/           ← bootstrap + install scripts
  bootstrap.sh     ← entry point for a fresh machine
  install.sh       ← main installer (called by bootstrap)
  packages.sh      ← package lists
  macos.sh         ← macOS defaults
  manifest.yaml    ← repos to clone + symlinks to create
docs/              ← system policy (symlinked into JD tree)
  POLICY.md
  policy.yaml
emacs/             ← Emacs config
alacritty/         ← terminal config
zsh/               ← shell config
tmux/              ← tmux config
git/               ← git config
```

## XDG directory layout

| Role | Path | What goes here |
|------|------|----------------|
| Config | `~/.config/<app>/` | Settings, init files — symlinked from this repo |
| Data | `~/.local/share/<app>/` | Packages, databases, persistent state |
| Cache | `~/.cache/<app>/` | Throwaway files, compilation cache |

## Johnny Decimal integration

This repo is the source of truth for system policy. The JD tree has symlinks back:

```
~/Documents/00-09 System/00 System/00.00 System - Meta/POLICY.md → ~/repos/dotfiles/docs/POLICY.md
~/Documents/.../06.03 Dotfiles                                   → ~/repos/dotfiles/
```
