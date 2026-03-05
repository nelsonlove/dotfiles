# Johnny Decimal — System Policy

> Living document. Canonical source of truth for conventions, structure, and filing rules.
> Last updated: 2026-03-01

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
| `xx.00` | **Category meta** | Agent workspace, config, templates, README. Parallel to `x0` at the area level. No name suffix required. |
| `xx.01` | **Unsorted** | Category-level inbox. Stuff that belongs in this category but hasn't been filed to a specific ID yet. |
| `xx.02+` | **Content** | Named by subject. Real filed content. |

### Area meta (`x0`)
Pattern: `x0 Meta - [Area Name]`
Purpose: area-level reference material, templates, conventions.
Exception: `00-09 Meta` is itself meta — `00 Indices` breaks the pattern and that's fine.

Each `x0` directory should contain a `README.md` documenting:
- What the area covers and its boundaries
- Setup or tooling needed for that area
- Conventions specific to that area
- Links to related resources

These READMEs are the first thing a human or agent reads when working in an area. System-related READMEs (e.g., `00`, `06`, `90`) are version-controlled in the dotfiles repo and symlinked into JD.

## Capture System (`01 Capture`)

Category `01` is the system-wide intake. Items flow through here on their way to proper JD locations.

### Two-tier triage

```
01.xx (Capture)  →  xx.01 (Category unsorted)  →  xx.yy (Final ID)
```

**Tier 1 (Capture → Category):** Quick sort. "This is a health thing" → `jd mv file 13.01`.
An agent or human just needs to know the domain.

**Tier 2 (Category → ID):** Detailed filing. "This is specifically lab results" → `jd mv file 13.05`.
Domain agents handle this — they know the context.

You don't have to do both tiers at once. Tier 1 is a fast sweep; Tier 2 happens when someone with domain knowledge is available.

### Capture buckets

Buckets are either **sources** (stuff flows in automatically) or **destinations** (staging for a blocked action).

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
The orphan detector skips `01 Capture` — unfiled items here are expected.

## Symlinks

### Direction
- **Into JD (preferred):** External resources get a symlink inside the JD tree.
- **Out of JD (exception):** Sync-sensitive dirs (git repos, XDG config) live outside iCloud and get symlinked FROM JD. Avoids iCloud/sync conflicts. See **Developer Environment** below.

### External drives
- Some IDs are symlinks/aliases to external drives (Seagate, LaCie, Extreme SSD).
- If the drive is unplugged, the symlink is broken. This is expected — `jd validate` reports it but doesn't treat it as an error.
- External drives have their own indices at `00.03 External drives`.
- The `jd` CLI skips broken symlinks during indexing.

### macOS aliases
- Aliases (`.alias` files) are different from symlinks. They survive file moves but are harder to detect programmatically.
- Prefer symlinks over aliases for JD purposes.

## Developer Environment

### Repositories (`~/repos/`)

Git repos cannot live on iCloud Drive — `.git` internals get corrupted by iCloud sync (placeholder stubs, conflict copies, pack file corruption).

**Policy:**
- All git repos live in `~/repos/` (short shell path, outside iCloud)
- `~/Documents/90-99 Projects/92 Repositories` is a symlink to `~/repos/`
- Repos are filed semantically in JD via symlinks from anywhere in the tree to `~/repos/<name>/`
- Repo folder names are plain (no JD IDs, no spaces) — the JD ID lives on the symlink, not the repo
- Not all repos live in `~/repos/` — some live where they technically must (e.g., dotfiles at `~/.config/`)
- Those still get a JD symlink pointing to their real location

**Finding repos:**
- All repos: `ls ~/repos/`
- JD locations: `find ~/Documents -type l -lname '*/repos/*'`

**Example:**
```
~/repos/harborview-tools/                          ← real repo
~/Documents/60-69 Work/61 Projects/61.03 Harborview Tools → ~/repos/harborview-tools/
```

### XDG directory layout

Config, data, and cache are separated per the XDG Base Directory spec:

| Role | Path | Contents |
|------|------|----------|
| Config | `~/.config/<app>/` | Settings, init files, dotfiles |
| Data | `~/.local/share/<app>/` | Packages, databases, persistent state |
| Cache | `~/.cache/<app>/` | Throwaway files, compilation cache |

Apps that dump data into `~/.config/` (e.g., Claude Desktop session transcripts, GitHub Copilot session blobs) should be `.gitignore`'d — only actual config files get version-controlled.

### Dotfiles

The dotfiles repo is a git repo containing config for all apps. It lives at `~/.config/` and is tracked on GitHub.

- `~/.config/` IS the repo working tree
- App configs are subdirectories: `~/.config/emacs/`, `~/.config/alacritty/`, `~/.config/tmux/`, etc.
- `.gitignore` excludes app-managed state (session data, caches, auto-generated files)
- JD symlink: `06.03 Dotfiles → ~/.config/`

### Bootstrapping a new machine

1. Sign into iCloud, wait for Documents to sync
2. Open Terminal
3. Policy docs are available at `~/Documents/00-09 Meta/00 Indices/00.00 Meta/`
4. Clone dotfiles: `git clone <repo> ~/.config/` (or pull from GitHub)
5. Run install script: `~/.config/install/bootstrap.sh`
   - Installs Homebrew, git, CLI tools
   - Creates `~/repos/`
   - Clones repos listed in manifest
   - Creates JD symlinks in Documents tree
6. JD symlinks from iCloud will resolve once repos are cloned to the same paths

## Documentation conventions

### Convention files

| File | Purpose | Auto-loaded? |
|------|---------|--------------|
| `README.md` | What this is, conventions, context. For humans and agents. | No — must be read explicitly |
| `CLAUDE.md` | Claude Code session instructions. Rules, preferences, constraints. | Yes — auto-loaded by Claude Code |

- **README.md** goes in any JD ID or `x0` meta dir that needs documentation. It's the universal "read this first" file.
- **CLAUDE.md** goes only in directories where Claude Code sessions run (repos, `~/.config/`). It's for tool-specific instructions, not general documentation.
- Don't duplicate content between them. README.md is context; CLAUDE.md is directives.

### Agent orientation

**Before working in any JD ID, agents must read:**
1. The `README.md` in the target ID (if it exists)
2. The `README.md` in the area's `x0` meta dir (for area-level conventions)
3. The `CLAUDE.md` in the working directory (auto-loaded for Claude Code)

This establishes context, conventions, and boundaries before any work begins.

### JD IDs as topic buckets

A JD ID covers a *topic*, not a single file or repo. An ID can contain:
- README.md (context and conventions)
- Symlinks to repos in `~/repos/`
- Documents, exports, reference material
- Multiple repos if the topic warrants it

Example:
```
06.13 Apple Notes/
  README.md                    ← conventions for how Apple Notes is used
  apple-notes-cli/             → ~/repos/apple-notes-cli/  (symlink)
  apple-notes-mcp/             → ~/repos/apple-notes-mcp/  (symlink)
```

`92 Repositories` is a staging area for repos that haven't been filed to their semantic home. Repos should migrate out of 92 into the JD ID that matches their topic.

## Agent Integration

### Workspace vs. JD
- Agent workspaces (`~/.openclaw/workspace-*`) hold the agent's **mind**: SOUL.md, MEMORY.md, AGENTS.md, skills/, memory/.
- JD `xx.00` dirs hold the agent's **output**: reports, drafts, generated files, artifacts.
- Agents read from anywhere in JD but write artifacts to their scoped categories.

### Agent scoping (`jd.yaml`)
Each agent workspace can declare its JD scope:

```yaml
agent: kin
scopes:
  - 22  # Mom
  - 24  # Tilly
  - 26  # Divorce
```

Agents file artifacts to `xx.00` within their scope. The `jd` CLI is the interface — agents use `jd which`, `jd mv`, `jd cp`, `jd new`.

### Filing workflow
1. Agent produces an artifact
2. Agent knows the domain → `jd mv artifact.pdf xx.00` (into category meta)
3. Agent doesn't know → `jd mv artifact.pdf 01.01` (into capture unsorted)
4. Triage pass files it properly

## Naming Conventions

- Areas: `XX-XX Name` (hyphen, not en-dash)
- Categories: `XX Name`
- IDs: `XX.YY Name` (or just `XX.YY` for meta dirs)
- Use sentence case for names
- No trailing spaces
- Avoid special characters that break shell commands (`:`, `*`, `?`)

## Known Issues (as of 2026-03-01)

Track these in `jd validate`. Current state:

- **Category 22 Mom** uses `21.xx` numbering — needs `jd renum` to fix
- **Duplicate IDs:** 06.15, 13.05, 73.04 — need renumbering
- **Broken symlinks:** 2 LaCie SSD links (drive unplugged), 1 in Music notes
- **Orphans:** 3 Obsidian vaults in `02 Notes`, `jobfish` in `61`, `quickbase-cli` in `64`

## CLI Reference

```
jd which <id>              Resolve ID to filesystem path
jd mv <source> <id>        Move file/dir into JD
jd cp <source> <id>        Copy file/dir into JD
jd new <id> [name]         Create new ID folder
jd rename <id> <new-name>  Rename (keeps number)
jd renum <old-id> <new-id> Renumber (keeps name, can move across categories)
jd init <category>         Bootstrap xx.00 + xx.01 for a category
jd init-all [--dry-run]    Bootstrap all categories
jd search <query>          Fuzzy search by name
jd index [area|category]   Print tree (filterable)
jd validate                Consistency report
jd json                    Machine-readable full index
jd generate-index          Write 00.00 Index.md + jd.json
```
