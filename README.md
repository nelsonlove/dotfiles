# Dotfiles

Personal system configuration and bootstrap for macOS.

## Scope

This repo owns:
- **Config files** — shell, editor, terminal, git, tmux
- **Inventory dumps** — Brewfile, pipx-list, uv-tools, cargo-list (see `install/REPRODUCIBILITY.md` for the gap matrix)
- **Install/bootstrap scripts** — partial; see Status below
- **System policy docs** — JD conventions, XDG layout, repo management
- **Manifest** — what repos to clone, where to symlink them

This repo does NOT yet own:
- **macOS `defaults`** — system preferences (phase 2)
- **`com.nelson.*.plist` launchagents** — Nelson-authored timers (phase 2)
- **TCC grants, SSH/GPG/cloud-CLI auth** — out of scope by design (see REPRODUCIBILITY.md)

This repo does NOT own:
- The JD CLI (`~/repos/jd-tools`) — separate repo, pulled in during bootstrap
- Project repos — cloned per the manifest
- The JD tree itself — lives on iCloud Drive, wired up by symlinks

## Bootstrap

> **Status:** `install/bootstrap.sh` is a Nix-darwin first-build
> script, but Nix is not currently active on this machine (verified
> 2026-06-10). The inventory files in `install/` (Brewfile,
> pipx-list.txt, etc.) are inventory-only for now — no installer
> consumes them yet. Reapplying state on a fresh machine is currently
> a manual exercise. See `install/REPRODUCIBILITY.md` for the gap
> matrix and `install/refresh-inventory.sh` for the dump-everything
> command.

Target (not yet current) flow:

```bash
# On a fresh Mac:
curl -fsSL https://raw.githubusercontent.com/nelsonlove/dotfiles/main/install/bootstrap.sh | bash
```

Eventually:
1. Installs Xcode CLI tools + Homebrew
2. Clones this repo to `~/repos/dotfiles`
3. Symlinks configs into `~/.config/`
4. Installs packages from Brewfile + pipx-list.txt + uv-tools.txt + cargo-list.txt
5. Applies macOS defaults
6. Clones the JD CLI and other repos from the manifest
7. Creates JD symlinks in the Documents tree

## Layout

```
install/                  ← bootstrap + inventory
  bootstrap.sh            ← Nix-darwin first-build (see Status above)
  manifest.yaml           ← repos to clone + symlinks to create
  REPRODUCIBILITY.md      ← gap matrix: what's declared, what isn't
  refresh-inventory.sh    ← dump all inventoried surfaces in one pass
  Brewfile                ← formulae + casks + taps + Mac App Store
  pipx-list.txt           ← pipx-installed apps
  uv-tools.txt            ← uv tools
  cargo-list.txt          ← cargo --globals
docs/                     ← system policy (symlinked into JD tree)
  POLICY.md
emacs/                    ← Emacs config (standalone, not Doom)
alacritty/                ← terminal config (TOML)
zsh/                      ← shell config (zsh + omz + p10k)
tmux/                     ← tmux config
git/                      ← git config
doom/                     ← Doom Emacs DOOMDIR
karabiner/                ← Karabiner-Elements rules
micro/                    ← micro editor
gh/                       ← gh CLI config
jd/                       ← johnnydecimal config
aerospace/                ← AeroSpace config (retired tool; kept as reference)
backlog/                  ← backlog.md project notes
proselint/                ← proselint config
aws/                      ← AWS CLI config
nix/                      ← nix-darwin host configs (Nix currently paused)
hosts/                    ← per-host overrides
home/                     ← home-manager defaults
overlays/                 ← nix overlays
inactive/                 ← retired configs kept as reference
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
