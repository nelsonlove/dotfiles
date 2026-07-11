# claude — Claude Code user config

Synced portion of `~/.claude/`. Symlinked into place by `install.sh` via
`manifest.yaml` `home_symlinks` (`ln -sfn`, same as everything else).

## What lives here

- `settings.json` — user-level settings: model, theme, permissions,
  `enabledPlugins` + `extraKnownMarketplaces` (plugins reinstall themselves
  from the marketplaces on a fresh machine — no plugin files are synced), and
  `autoMemoryDirectory`, which points auto-memory at the vault
  (`~/obsidian/00-09 System/03 LLMs & agents/03.17 Claude Code memories`) so
  memories ride Obsidian Sync across machines instead of this repo.
- `skills/` — user-level skills (`pickle`, `tickle`, …). New skills written
  to `~/.claude/skills/` land here automatically through the symlink; commit
  them when they settle. Exception: `skills/ops/` is a clone of
  `callumalpass/ops` (gitignored here) — on a fresh machine,
  `git clone https://github.com/callumalpass/ops ~/.claude/skills/ops`.

## What deliberately does NOT live here

- **Secrets** — `env.GITHUB_PERSONAL_ACCESS_TOKEN` and friends belong in
  `~/.claude/settings.local.json` (machine-local, never committed). If a
  secret shows up in `settings.json`, move it there before committing.
- `~/.claude.json` — OAuth tokens, trust dialogs. Machine-local.
- `~/.claude/projects/` — session transcripts (machine-local) and the
  per-project `memory/` entries, which on this machine are symlinks into the
  vault store above.
- Caches and runtime state: `plugins/cache/`, `shell-snapshots/`,
  `history.jsonl`, `statsig/`, `file-history/`, etc. All regenerate.

## Fresh machine

`install.sh` symlinks this dir's contents into `~/.claude/`; sign in to
Claude Code (auth is per-machine), and put the GitHub PAT into
`~/.claude/settings.local.json`. Memories arrive via Obsidian Sync.
