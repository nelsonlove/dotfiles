# Johnny Decimal — System Policy

> Living document. Canonical source of truth for JD structure and filing rules.
> Last updated: 2026-03-30

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
| `xx.00` | **JDex (category meta)** | Named `JDex for category xx`. Agent workspace, config, templates, README. |
| `xx.01` | **Inbox** | Named `Inbox for category xx`. Category-level inbox for items not yet filed to a specific ID. |
| `xx.02` | **Task & project management** | Named `Task & project management for category xx`. Proposals and planning docs. |
| `xx.03+` | **Content** | Named by subject. Real filed content. |

### Area meta (`x0`)
Pattern: `x0 Management of area XX-XX`
Purpose: area-level reference material, templates, conventions.

Each `x0` directory should contain a `README.md` documenting what the area covers, its boundaries, setup, and conventions.

## Capture System (`01 Capture`)

Category `01` is the system-wide intake. Items flow through here on their way to proper JD locations.

### Two-tier triage

```
01.xx (Capture)  →  xx.01 (Category inbox)  →  xx.yy (Final ID)
```

**Tier 1 (Capture → Category inbox):** Quick sort. "This is a health thing" → `jd mv file 13.01`.
**Tier 2 (Category inbox → ID):** Detailed filing. "This is specifically lab results" → `jd mv file 13.05`.

You don't have to do both tiers at once. Tier 1 is a fast sweep; Tier 2 happens when domain knowledge is available.

### Capture buckets

| Bucket | Purpose |
|--------|---------|
| `01.00 JDex for category 01` | Capture policy, auto-sort rules, agent config |
| `01.01 Inbox for category 01` | True unknown — needs human decision |
| `01.10 Repositories for category 01` | Repos awaiting placement in the JD tree |
| `01.11 To Photos` | Waiting for import to Photos |
| `01.12 To Contacts` | Waiting for import to Contacts |
| `01.13 To LaCie SSD` | Waiting for external drive |
| `01.14 To Extreme SSD` | Waiting for external drive |
| `01.15 To Calibre or iBooks` | Waiting for import to library app |
| `01.16 To Bookends` | Waiting for import to reference manager |
| `01.17 To Calendar` | Waiting for import to Calendar |
| `01.18 To Day One` | Waiting for import to Day One |
| `01.19 To Obsidian` | Waiting for import to Obsidian |

Capture buckets are destination-based ("To X") — items wait here until the target app or device is available.

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
