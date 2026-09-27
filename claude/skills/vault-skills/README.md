# vault-skills (Claude Code plugin)

The landing plugin for skills and agents authored as notes in Nelson's Obsidian vault. It carries no vault content of its own: the exporter writes the vault's projection into this directory, and Claude Code loads it in place.

The exporter is the **skills satellite of [obsidian-mcp-suite](https://github.com/nelsonlove/obsidian-mcp-suite)** — `packages/skills`, published as `@vault-mcp/skills`. This plugin ships no MCP server of its own.

## What is tracked and what is generated

- `.claude-plugin/plugin.json` — the manifest. Static, tracked.
- `skills/new-skill/` — the static authoring skill and its bundled `conventions.md`. Tracked; this is the plugin's own payload, not vault output.
- `skills/`, `agents/`, `commands/`, `hooks/` — landing directories the exporter writes into. Their generated contents are git-ignored, along with the `.vault-skills-manifest.json` the exporter drops beside them; only the `.gitkeep` placeholders are tracked, so a fresh checkout already has the directories the exporter expects.

A vault note becomes one of four things, and each lands in its own directory: a `skill` in `skills/<name>/SKILL.md`, an `agent` in `agents/<name>.md`, a `command` in `commands/<name>.md`, and a `policy` in no file at all — its body is injected into the prompts of the agents it scopes. `hooks/hooks.json` is written too: it is not a note type, and the bundled `conventions.md` does not describe it, but the exporter emits it — the installed copy carries one, listed in its own `.vault-skills-manifest.json`.

Do not hand-edit the generated files. The source of truth is the vault note; edit it and re-export.

## How it gets loaded

The plugin lives in the dotfiles repository at `claude/skills/vault-skills`, and `~/.claude/skills` is a symlink to `claude/skills`, so Claude Code finds it at `<config>/skills/vault-skills/` and **loads it in place** as `vault-skills@skills-dir`. There is no marketplace step and no cache copy: the exporter writes into this directory and the loaded plugin is the same files. Nothing needs installing on a fresh machine beyond the symlink `install.sh` already makes.

Skills invoke as `/vault-skills:<name>`; agents as `vault-skills:<name>`. The exporter builds a tree from each note's `parent` edge — every agent owns its skills, preloaded, and delegates to its child agents.

## History

Until 2026-09-26 this plugin lived at `claude-code/` inside `nelsonlove/obsidian-vault-skills`, which GitHub has had archived since 2026-08-11, and the catalogue sourced it from there. Nelson ruled that vault-skills is not retired, so the plugin moved, and the exporter is being rebuilt as the suite satellite named above.

It moved twice in a day. It was first landed in the marketplace repository `nelsonlove/claude-code-plugins` (PR #62), which was closed unmerged once the export target was proved: with a plugin under `<config>/skills/` loading in place, a catalogued copy of the same plugin would load beside it, twice. So it lives here instead, the catalogued `vault-skills@claude-code-plugins-mac` was uninstalled, and this branch removes that entry from `claude/settings.json`. The files are the ones from that closed branch; only this README's loading and history sections are revised, because they described the marketplace route that was abandoned.
