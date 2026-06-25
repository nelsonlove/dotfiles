# Dotfiles

Personal system configuration and bootstrap for macOS.

## Scope

This repo owns:
- **Config files** — shell, editor, terminal, git, tmux
- **Inventory dumps** — Brewfile, pipx-list, uv-tools, cargo-list (see `install/REPRODUCIBILITY.md` for the gap matrix)
- **Install/bootstrap scripts** — `bootstrap.sh` + interactive `install.sh` (see Bootstrap below)
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

The repo is public, so the one-liner works on a fresh Mac with no auth:

```bash
curl -fsSL https://raw.githubusercontent.com/nelsonlove/dotfiles/main/install/bootstrap.sh | bash
```

`bootstrap.sh` does the unattended prerequisites, then hands off to the
interactive `install.sh`:

1. **bootstrap.sh** — Xcode CLI tools → Rosetta (Apple Silicon) →
   Homebrew → clone repo → launch `install.sh`
2. **install.sh** — symlinks configs into `~/.config/` (from
   `manifest.yaml`), then opens a pick-what-you-want menu of package
   **groups** and `brew bundle`s the selection

You don't have to install everything. The installer groups packages
(shell, editor, dev, cloud, media, apps, games, …) and you toggle which
groups to install. **Core** (Claude Code + Obsidian) is always included,
so the minimum install is a working Claude Code + Obsidian. Non-interactive
shortcuts: `install.sh --core` (minimum) or `install.sh --all` (everything).

The groups come from `# group:NAME` tags on each entry in `Brewfile`.
Dependencies (tagged `_dep`) are hidden from the menu — `brew` resolves
them automatically. Re-run `install.sh` anytime to add more groups.

> **Still manual / phase 2:** macOS `defaults`, launchagents, and the JD
> CLI / project-repo cloning + JD-tree symlinks are not yet wired into
> `install.sh`. See `install/REPRODUCIBILITY.md` for the full gap matrix
> and `install/refresh-inventory.sh` for the dump-everything command.
> Nix is not used for the Mac (it remains active only for the pi400 host).

## Layout

```
install/                  ← bootstrap + installer + inventory
  bootstrap.sh            ← fresh-machine prereqs, then runs install.sh
  install.sh              ← interactive group-picker installer
  manifest.yaml           ← repos to clone + symlinks to create
  REPRODUCIBILITY.md      ← gap matrix: what's declared, what isn't
  refresh-inventory.sh    ← dump all inventoried surfaces in one pass
  merge-brewfile-tags.py  ← re-applies # group: tags after a brew dump
  Brewfile                ← formulae + casks + taps + mas, # group:-tagged
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
