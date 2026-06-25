# Reproducibility surfaces

For each component class on Nelson's macOS workstation: **is its state
declared somewhere this repo can re-apply?** This file is the index;
inventory dumps live alongside it (`Brewfile`, `pipx-list.txt`, etc.).

The goal was **inventory-only** first — spot every place declarative
documentation is missing. As of the TUI installer, `install/install.sh`
now *consumes* the Brewfile (grouped by `# group:` tags); the other dumps
(pipx/uv/cargo) remain inventory-only.

Narrative discussion lives in the vault at
`00-09 System/04 Digital tools/04.11 Dotfiles.md` (why some surfaces
are intentionally undocumented, TCC limitations, etc.).

## Status

Legend: ✅ declared and refreshed via this repo · 📥 inventory-only
(dump exists but no installer consumes it yet) · ❌ gap (no
declaration at all) · ⏸ deferred (declarable but later phase) · 🚫
intentionally not declared (sensitive or not declarable on macOS).

| Surface | Manifest in repo | Refresh command | Status |
|---|---|---|---|
| Symlinks + repo list | `install/manifest.yaml` | hand-edit | ✅ |
| Shell, git, tmux, editor configs | `zsh/`, `git/`, `tmux/`, `doom/`, etc. | git-tracked | ✅ |
| Doom Emacs packages | `doom/packages.el` | `doom sync` | ✅ |
| Homebrew formulae + casks + taps + mas | `install/Brewfile` (`# group:`-tagged) | `install/refresh-inventory.sh` (dump + tag-merge) | ✅ |
| Homebrew services | none | `brew services list` (no dump format) | ❌ |
| Homebrew tap trust | none | `brew tap-info --json` | ❌ |
| pipx apps | `install/pipx-list.txt` | `pipx list --short` | ❌ |
| uv tools | `install/uv-tools.txt` | `uv tool list` | ❌ |
| cargo --globals | `install/cargo-list.txt` | `cargo install --list` | ❌ |
| npm globals | `install/npm-globals.txt` | `npm ls -g --depth=0 --json` | ⏸ |
| pnpm globals | `install/pnpm-globals.txt` | `pnpm list -g --depth=0 --json` | ⏸ |
| Gem globals | `install/gems.txt` | `gem list --no-versions` | ⏸ |
| Mac App Store apps | (rolls into `install/Brewfile`) | covered by `brew bundle dump` | ❌ |
| Nelson's launchagents | `install/launchagents/com.nelson.*.plist` | manual copy from `~/Library/LaunchAgents/` | ❌ |
| macOS `defaults` | `install/defaults/*.plist` | per-domain `defaults export` | ⏸ phase 2 |
| TCC grants (Accessibility, FDA, Screen Recording, Automation) | n/a | not declarable without MDM | 🚫 |
| Login Items / SMAppService | per-app bundles | not centrally exposed by macOS | 🚫 |
| Claude Code config (`~/.claude/`) | external — `~/repos/claude-code-config` | separate repo, git-tracked | ✅ external |
| Claude Code plugin enable list | `~/.claude/settings.json` | inside claude-code-config repo | ✅ external |
| Vault content | external — Obsidian Sync | server-side | ✅ external |
| SSH keys | `~/.ssh/` | manual restore from 1Password | 🚫 by design |
| GPG keys | `~/.gnupg/` | manual restore from 1Password | 🚫 by design |
| Doppler / 1Password / cloud-CLI auth | various `~/.<tool>/` | server-side; per-machine `<cli> login` | 🚫 by design |
| Tailscale device + ACL | tailscale.com | account-level | ✅ external (server-side) |
| Cloudflare Access policies (for `obsidian-mcp.nelson.love` etc.) | Cloudflare dashboard | account-level | ✅ external (server-side) |

## Refresh ritual

Run `install/refresh-inventory.sh`. It writes each dump in place,
showing per-surface success/skip status. Review `git diff`, decide
whether to commit. Surfaces marked `🚫` and `⏸` are skipped.

Cadence: at least weekly during active config churn; quarterly when
stable. Always before a known machine wipe.

## Commit policy

The dumps are git-tracked, not gitignored. After running the
refresh, **`git diff install/` IS the drift signal** — what changed
since the last commit. Commit changes you want to keep (a new
`pipx install`, a `brew install`); discard noisy diffs (transient
build-time deps, version-only churn). The commit history of these
files becomes a record of deliberate config evolution; uncommitted
local state becomes the unblessed tail.

This is why first-cut scope is "inventory-only": you can't get
drift visibility without committing the dump format, but you can
get it without writing an installer that consumes it.

## Per-surface notes

### Homebrew

`brew bundle dump --force` covers formulae + casks + taps + Mac App
Store + (if configured) VS Code extensions + Whalebrew. One Brewfile
is the right place — don't fragment into separate `formulae.txt` /
`casks.txt` files. Services state (`started` / `none`) is NOT captured
by Brewfile — that's a separate gap.

**Group tags.** Each `brew`/`cask`/`mas` line carries a trailing
`# group:NAME` tag (e.g. `# group:dev`). `install.sh` reads these to
offer a pick-what-you-want menu; `core` is always installed, `_dep`
entries are hidden (brew resolves them as dependencies). A plain
`brew bundle dump --force` would strip these tags, so the refresh goes
through `refresh-inventory.sh`, which backs up the tagged file and
re-applies the tags afterward (`merge-brewfile-tags.py`). New, untagged
packages are reported on stderr and default to `_untagged` until you
assign a group. The tag-merge also carries over the non-`brew bundle`
lines (`cargo`/`uv`/`npm`), which a raw dump would drop.

**Staleness flag.** Apps (casks/mas) confirmed opened recently also carry
`used:recent`. The installer skips not-recently-used apps by default
(toggle with `s` in the menu or `--include-stale`); core and CLI tools are
never skipped. The `used:recent` set is a manual first pass derived from
the CoreDuet `knowledgeC.db` usage stream (`/app/usage`), which only
retains ~3 weeks — so it's a "definitely active" allowlist, not a complete
usage history. CLI-tool staleness is intentionally not flagged: shell
history misses indirect/aliased/editor-spawned invocations, so absence
isn't a reliable stale signal.

Trust state for third-party taps is also not captured. With 14
untrusted taps currently in use (`bun`, `wrangler-cli`, `supabase`,
`minio`, `twilio`, etc.), `brew outdated` is silently blind for those.
A separate `brew tap-info --json` dump would close this; not in scope
for first cut.

### pipx / uv / cargo

All produce `<app> <version>` style output. The dumps capture the list
of installed apps; restoring is `xargs -L1 pipx install <app>` etc.
Version pinning is intentionally not captured — pipx/uv resolve to
latest by default and that matches Nelson's actual workflow.

### Mac App Store

Covered by `brew bundle dump` via the `mas` lines. No separate
`mas-list.txt` is needed — but `mas` itself must be installed first
for the dump to include MAS entries. Bootstrap order matters.

### macOS defaults

Out of scope for first cut. The general approach is per-domain
`defaults export <domain> install/defaults/<domain>.plist` — for
example `defaults export com.apple.dock install/defaults/dock.plist`.
The hard part is enumerating which domains Nelson has customized;
that's an interactive audit, not a generic dump. Phase 2.

### TCC grants

Modern macOS (Big Sur+) doesn't expose a sanctioned read-modify-write
path for `/Library/Application Support/com.apple.TCC/TCC.db`. Reading
requires Full Disk Access on the reader; writing requires user
interaction. Without MDM (`PPPC` profiles via Jamf/Munki/etc.), the
only durable path is a checklist of "after restore, grant
Accessibility to: Karabiner, Hazel, Hammerspoon, etc." Documented as a
checklist, not a dump.

### Why some surfaces are 🚫 not declared

Secrets and per-machine auth state intentionally don't live in this
repo — restoration is via 1Password and per-tool `<cli> login` flows.
The audit gap there isn't "we need to dump these" but "we need a
bootstrap checklist of which `<cli> login` flows to run after a fresh
install." That checklist is a separate concern from this file.

## What this file deliberately does NOT cover

- `~/.cache/`, `~/.local/share/`, `~/.local/state/` — derived state,
  regenerated by tools as needed. The reproducibility audit at
  `04.12 System bird's-eye view.md` flagged stale caches but they're
  not load-bearing.
- Project repo contents — covered by `install/manifest.yaml` (which
  repos to clone) plus each repo's own bootstrap.
- Vault content — Obsidian Sync handles it.
- Tailscale / Cloudflare / GitHub account state — server-side, not in
  scope for a dotfiles repo.
