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


def emit(context):
    """Write one SessionStart additionalContext payload to stdout."""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": context,
        }
    }))


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
        if ".trash" not in p
        and Path(p).stem == Path(p).parent.name  # folder notes only
        and has_frontmatter_audience(p)
    ]


def norm(stamp):
    """Comparable form of a stamp: 'x' placeholders (e.g. 21:2x) sort as 0,
    so a sloppy stamp never outranks a later real one."""
    return stamp.replace("x", "0")


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
        # Say so out loud. A silent return here is indistinguishable from "the
        # log was read and had nothing", so a vault move that strands the file
        # would go unnoticed for as long as it took someone to wonder why the
        # channel was quiet — and a session that cannot see the log is liable
        # to recreate it somewhere wrong.
        emit(
            f"Cross-session log: NOT FOUND under {VAULT}. The coordination channel is "
            "unreadable this session — do not assume it is empty and do not create a new "
            f"one; its home is '00-09 System/03 Agents/03.16 Cross-session log/CROSS-SESSION.md'."
        )
        return

    text = log.read_text(errors="replace")
    entries = split_entries(text)
    if not entries:
        emit(
            f"Cross-session log: found at {log} but it contains no parseable entries "
            "(expected '## YYYY-MM-DDTHH:MM' headings). Treat as unread, not as empty."
        )
        return

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    state_file = STATE_DIR / re.sub(r"[^A-Za-z0-9._-]", "_", session_id)
    last = state_file.read_text().strip() if state_file.exists() else ""
    if not last:
        last = (datetime.now() - timedelta(hours=FIRST_RUN_WINDOW_HOURS)).strftime(
            "%Y-%m-%dT%H:%M"
        )

    unread = [(s, e) for s, e in entries if norm(s) > norm(last)]

    channels = channel_index()
    chan_lines = "\n".join(f"- {c}" for c in channels) or f"- {log}"

    if unread:
        # Page oldest-first by stamp (file order is not reliably chronological):
        # entries beyond the cap stay unread — the state stamp only advances to
        # a value strictly below every unshown entry — so they surface on the
        # next start instead of being silently marked read.
        unread.sort(key=lambda pair: norm(pair[0]))
        shown = unread[:MAX_ENTRIES]
        while len(shown) > 1 and sum(len(e) for _, e in shown) > MAX_CHARS:
            shown.pop()
        remaining = len(unread) - len(shown)
        body = "\n\n".join(e for _, e in shown)
        note = (
            f"[{remaining} newer unread entries not shown — read them in the file now; "
            "they will also resurface at the next session start]\n\n"
            if remaining else ""
        )
        context = (
            f"UNREAD CROSS-SESSION LOG ENTRIES ({log}):\n"
            "Per the 'Cross-session log reading discipline' rule in CLAUDE.md, read each entry below in full "
            "and give each a disposition (act / reply in the log / consciously dismiss). "
            "A reply is mandatory if an entry names your scope, files, or claims.\n\n"
            f"{body}\n\n{note}"
            f"Cross-session channels discovered (audience: frontmatter):\n{chan_lines}"
        )
        if remaining:
            min_unshown = min(norm(s) for s, _ in unread[len(shown):])
            below = [norm(s) for s, _ in shown if norm(s) < min_unshown]
            # No candidate below the unshown floor (a stamp tie across the cap
            # boundary): keep the old stamp — tied entries reshow next start
            # rather than any being lost.
            new_state = max(below) if below else last
        else:
            new_state = max(norm(s) for s, _ in shown)
    else:
        context = (
            f"Cross-session log: no unread entries since {last} ({log}). "
            "The reading-discipline rule in CLAUDE.md still applies to entries arriving mid-session."
        )
        new_state = last

    emit(context)
    # State advances only after the context was successfully emitted, and only
    # to the last entry actually shown — injection of an entry, not attestation
    # of the whole file, is what the stamp records.
    state_file.write_text(norm(new_state))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
