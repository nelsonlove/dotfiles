# Johnny Decimal — System Policy

> Living document. Canonical source of truth for JD structure and filing rules.
> Last updated: 2026-03-08

## Principles

1. **The filesystem is the canonical source of truth.** All other systems (Apple Notes, OmniFocus, email, Obsidian) hold sparse subsets.
2. **Folders are created on-demand.** No empty mirroring across apps. A folder exists in an app only when it has content there.
3. **JD-aware apps signal awareness via a meta marker** (e.g., an `XX-XX` area folder). If the marker is absent, the app is not JD-managed.
4. **Agents use the `jd` CLI.** No hardcoded paths. `jd which <id>` resolves everything.

## Structure

### Areas (`XX-XX Name`)
Top-level groupings. Max 10 (0-9).

### Categories (`XX Name`)
Two-digit numbered directories inside areas. Each area holds up to 10 categories.

### IDs (`XX.YY Name`)
Dotted notation inside categories. Up to 100 per category (00-99).

## Reserved IDs

Every category follows this convention:

| ID     | Purpose | Notes |
|--------|---------|-------|
| `xx.00` | **Category meta** | Agent workspace, config, templates, README. Parallel to `x0` at the area level. |
| `xx.01` | **Unsorted** | Category-level inbox. Belongs in this category but hasn't been filed to a specific ID yet. |
| `xx.02+` | **Content** | Named by subject. Real filed content. |

### Area meta (`x0`)
Pattern: `x0 Meta - [Area Name]`
Purpose: area-level reference material, templates, conventions.

Each `x0` directory should contain a `README.md` documenting what the area covers, its boundaries, setup, and conventions.

## Capture System (`01 Capture`)

Category `01` is the system-wide intake. Items flow through here on their way to proper JD locations.

### Two-tier triage

```
01.xx (Capture)  →  xx.01 (Category unsorted)  →  xx.yy (Final ID)
```

**Tier 1 (Capture → Category):** Quick sort. "This is a health thing" → `jd mv file 13.01`.
**Tier 2 (Category → ID):** Detailed filing. "This is specifically lab results" → `jd mv file 13.05`.

You don't have to do both tiers at once. Tier 1 is a fast sweep; Tier 2 happens when domain knowledge is available.

### Capture buckets

| Bucket | Type | Purpose |
|--------|------|---------|
| `01.00` | meta | Capture policy, auto-sort rules, agent config |
| `01.01 Unsorted` | catch-all | True unknown — needs human decision |
| `01.02 Downloads` | source | Browser download dir (symlink from ~/Downloads) |
| `01.03 Screenshots` | source | macOS screenshot landing zone |
| `01.04 Scans` | source | Scanner output dir |
| `01.05 To LaCie SSD` | destination | Waiting for external drive |
| `01.06 To Calibre` | destination | Waiting for import to library app |

Source buckets fill automatically. Destination buckets get emptied when blockers clear.

## Documentation conventions

`jd claude` collects files from each level's `xx.00` meta dir using a stem × extension search. These are the standard stems:

| Stem | Purpose | Loaded by |
|------|---------|-----------|
| `README` | What this is, conventions, context. For humans and agents. | `jd claude` |
| `TODO` | Open tasks and plans for this level. | `jd claude` |
| `CLAUDE` | Claude Code session instructions. Rules, preferences, constraints. | `jd claude` + Claude Code natively |
| `AUDIT` | Current-state audit of a tool, folder, or ID. Date at top for staleness. | `jd claude` |
| `TIMELINE` | Chronological history — events, decisions, milestones. Prefer `.org` for foldable content. | `jd claude` |
| `PLAN` | Committed implementation plan (post-decision, not a draft). | `jd claude` |

Extensions searched: `.md`, `.org`, `.txt` (in that order). README is context; CLAUDE is directives. Don't duplicate content between them.

### JD IDs as topic buckets

A JD ID covers a *topic*, not a single file or repo. An ID can contain READMEs, symlinks to repos, documents, exports, and multiple repos if the topic warrants it.

## Naming Conventions

- Areas: `XX-XX Name` (hyphen, not en-dash)
- Categories: `XX Name`
- IDs: `XX.YY Name` (or just `XX.YY` for meta dirs)
- Use sentence case for names
- No trailing spaces
- Avoid special characters that break shell commands (`:`, `*`, `?`)
