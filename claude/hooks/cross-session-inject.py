#!/usr/bin/env python3
"""SessionStart hook: inject unread cross-session log entries into context.

Reads the fleet CROSS-SESSION.md (found by name, never hardcoded), compares
against this session's last-injected stamp, and emits the unread entries as
additionalContext plus an index of any other cross-session channels
(folder notes carrying an `audience:` frontmatter field).

State: one stamp file per session id under ~/.local/share/cross-session-hook/.
Injection is not attestation — the reading-discipline rule in CLAUDE.md still
governs dispositions and "read through <stamp>" records.

Fail-safe: any error exits 0 with no output; session start is never blocked.
"""

import json
import re
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

VAULT = Path.home() / "obsidian"
STATE_DIR = Path.home() / ".local/share/cross-session-hook"
MAX_ENTRIES = 15
MAX_CHARS = 12000
FIRST_RUN_WINDOW_HOURS = 48
HEADING = re.compile(r"^## (20\d\d-\d\d-\d\dT[0-9:x]+)", re.M)


def find_log():
    for p in sorted(VAULT.rglob("CROSS-SESSION.md")):
        if ".trash" not in p.parts:
            return p
    return None


def has_frontmatter_audience(path):
    """True only when `audience:` sits inside the note's frontmatter block."""
    try:
        with open(path, errors="replace") as f:
            head = f.read(4096)
    except OSError:
        return False
    if not head.startswith("---\n"):
        return False
    fm_end = head.find("\n---", 4)
    if fm_end == -1:
        return False
    return re.search(r"^audience: ", head[4:fm_end], re.M) is not None


def channel_index():
    """Folder notes with an `audience:` frontmatter field, via one bounded grep."""
    try:
        out = subprocess.run(
            ["grep", "-rl", "--include=*.md", "^audience: ", str(VAULT)],
            capture_output=True, text=True, timeout=5,
        ).stdout
    except Exception:
        return []
    return [
        p for p in out.splitlines()
        if ".trash" not in p and has_frontmatter_audience(p)
    ]


def split_entries(text):
    """Return [(stamp, entry_text)] in file order."""
    matches = list(HEADING.finditer(text))
    entries = []
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        entries.append((m.group(1), text[m.start():end].rstrip()))
    return entries


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}
    session_id = str(payload.get("session_id") or "unknown")

    log = find_log()
    if log is None:
        return

    text = log.read_text(errors="replace")
    entries = split_entries(text)
    if not entries:
        return

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    state_file = STATE_DIR / re.sub(r"[^A-Za-z0-9._-]", "_", session_id)
    last = state_file.read_text().strip() if state_file.exists() else ""
    if not last:
        last = (datetime.now() - timedelta(hours=FIRST_RUN_WINDOW_HOURS)).strftime(
            "%Y-%m-%dT%H:%M"
        )

    unread = [(s, e) for s, e in entries if s > last]
    newest = max(s for s, _ in entries)
    state_file.write_text(newest)

    channels = channel_index()
    chan_lines = "\n".join(f"- {c}" for c in channels) or f"- {log}"

    if unread:
        dropped = max(0, len(unread) - MAX_ENTRIES)
        shown = unread[-MAX_ENTRIES:]
        body = "\n\n".join(e for _, e in shown)
        if len(body) > MAX_CHARS:
            body = body[-MAX_CHARS:]
            body = "[oldest entries truncated]\n" + body[body.index("\n## ") + 1:] if "\n## " in body else body
        note = f"[{dropped} older unread entries not shown — read them in the file]\n\n" if dropped else ""
        context = (
            f"UNREAD CROSS-SESSION LOG ENTRIES ({log}):\n"
            "Per the 'Cross-session log reading discipline' rule in CLAUDE.md, read each entry below in full "
            "and give each a disposition (act / reply in the log / consciously dismiss). "
            "A reply is mandatory if an entry names your scope, files, or claims.\n\n"
            f"{note}{body}\n\n"
            f"Cross-session channels discovered (audience: frontmatter):\n{chan_lines}"
        )
    else:
        context = (
            f"Cross-session log: no unread entries since {last} ({log}). "
            "The reading-discipline rule in CLAUDE.md still applies to entries arriving mid-session."
        )

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": context,
        }
    }))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
