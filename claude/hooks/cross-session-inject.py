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

# PACKAGE 8 (Nelson, 2026-09-29T02:13: "B and clear out the old entries, it's a loooong file", a one-week trial): below captain, a session reads only the RULINGS; captains and admirals keep the whole delta.
#
# A RULING, by its heading: the kind marker after the author is "— ruling" (em dash, en dash or hyphen, after a space), at the end, before a colon ("— ruling: Nelson …") or before a note in brackets ("- ruling (relayed)"); or "ruling executed:". Measured on the real log 2026-09-29: 115 end in "— ruling", 1 has "— ruling:", 0 have "ruling executed:", and no heading whose kind names a ruling is missed. The word "ruling" elsewhere is not the marker: a claim "— claim: for Nelson's … ruling" is a claim. The test's population case fails on any heading whose kind names a ruling and is not read as one, so a new form is caught there rather than dropped in silence.
RULING = re.compile(r"(?:^|\s)[—–-]\s*ruling\s*(?::|\(|$)|\bruling executed\s*:", re.I)
RULINGS_MAX_CHARS = 3000

# THE RANK is read the way the fleet scripts read it, from the one table (claude/bin/_fleet-ranks.sh, sourced, never copied): the job state's `template` first, through rank_of_agent; then the session's name in `claude agents --json --all`, through rank_of_name. If neither gives a rank, the session gets the WHOLE delta: failing toward more reading is safe, and toward less is not.
FLEET_RANKS = Path(__file__).resolve().parent.parent / "bin" / "_fleet-ranks.sh"
JOBS_DIR = Path.home() / ".claude/jobs"


def is_ruling(heading):
    return bool(RULING.search(heading))


def rank_via_table(fn, arg):
    try:
        out = subprocess.run(["bash", "-c", '. "$1" >/dev/null 2>&1 || exit 9; "$2" "$3"', "_", str(FLEET_RANKS), fn, arg],
                             capture_output=True, text=True, timeout=3).stdout.strip()
        r = int(out)
    except Exception:
        return None
    return None if r == 9 else r


def session_rank(session_id):
    """The session's rank number (-1 admiral … 3 lieutenant), or None when it cannot be told."""
    short = session_id[:8]
    template = ""
    try:
        template = json.loads((JOBS_DIR / short / "state.json").read_text()).get("template") or ""
    except Exception:
        pass
    if template and template not in ("bg", "claude"):
        r = rank_via_table("rank_of_agent", template)
        if r is not None:
            return r
    try:
        rows = json.loads(subprocess.run(["claude", "agents", "--json", "--all"], capture_output=True, text=True, timeout=3).stdout or "[]")
    except Exception:
        rows = []
    for row in rows if isinstance(rows, list) else []:
        if session_id in (row.get("sessionId"), row.get("id")) or short == row.get("id"):
            name = row.get("name") or ""
            if name:
                return rank_via_table("rank_of_name", name)
    return None


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

    # No vault on this host at all (the settings.json + hooks pair is shared
    # across machines, and not every machine carries ~/obsidian): the hook does
    # not apply, so stay silent. Warning here would fire on every single
    # session start of a vault-less machine, which is noise, not signal.
    if not VAULT.is_dir():
        return

    log = find_log()
    if log is None:
        # Vault present but no log in it — say so out loud. A silent return
        # here is indistinguishable from "the log was read and had nothing", so
        # a vault move that strands the file would go unnoticed for as long as
        # it took someone to wonder why the channel was quiet — and a session
        # that cannot see the log is liable to recreate it somewhere wrong.
        # The path below is a hint for that case only; find_log() still
        # discovers by name, so the log moving does not need an edit here.
        emit(
            f"Cross-session log: NOT FOUND under {VAULT}, though the vault exists. The "
            "coordination channel is unreadable this session — do not assume it is empty "
            "and do not create a new one. As of 2026-08-18 its home was "
            "'00-09 System/03 Agents/03.16 Cross-session log/CROSS-SESSION.md'; search "
            "the vault before concluding it is gone."
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

    # The rank is looked up only when there is something to show: it costs a bash and, for some sessions, a `claude agents` listing.
    rank = session_rank(session_id) if unread else None
    if rank is not None and rank >= 1:
        # BELOW CAPTAIN: rulings only. THE STAMP: it advances past every ruling shown, and past the claims and releases around them, which are not meant to be read below captain; it never passes a ruling that was not shown. With rulings left over the cap, it stops just below the first of them, so that ruling (and anything tied with it) comes back next start.
        unread.sort(key=lambda pair: norm(pair[0]))
        rulings = [(s, e) for s, e in unread if is_ruling(e.split("\n", 1)[0])]
        shown, used = [], 0
        for s_, e_ in rulings:
            if shown and used + len(e_) > RULINGS_MAX_CHARS:
                break
            shown.append((s_, e_)); used += len(e_)
        # A TIE ACROSS THE CAP: when the first ruling left out shares its stamp with the last one shown, the stamp could not move past either, and the same rulings would come back on every start. So the rest of that stamp's rulings are shown too, over the cap: a stamp group is shown whole.
        while len(shown) < len(rulings) and norm(rulings[len(shown)][0]) == norm(shown[-1][0]):
            shown.append(rulings[len(shown)])
        left = rulings[len(shown):]
        if left:
            floor = norm(left[0][0])
            below = [norm(s_) for s_, _ in unread if norm(s_) < floor]
            new_state = max(below) if below else last
        else:
            new_state = max((norm(s_) for s_, _ in unread), default=last)
        chan_lines = "\n".join(f"- {c}" for c in channel_index()) or f"- {log}"
        if shown:
            note = (f"[{len(left)} more rulings not shown: read them in the file now; they will also come back at the next session start]\n\n" if left else "")
            context = (
                f"UNREAD CROSS-SESSION LOG: RULINGS ONLY ({log}):\n"
                "You are below captain, so since Nelson's ruling of 2026-09-29 you read the RULINGS; claims and releases are left out. "
                "Before you edit a file, grep the log once for a claim on that path, and honour it. Do not start a Monitor on the log. "
                "Read each ruling in full and give it a disposition without restating it in chat. Say at most one line on what it changes for you. "
                "This is the 'Cross-session log reading discipline' rule in CLAUDE.md.\n\n"
                + "\n\n".join(e_ for _, e_ in shown) + "\n\n" + note
                + f"Cross-session channels discovered (audience: frontmatter):\n{chan_lines}"
            )
        else:
            context = (f"Cross-session log: no new rulings since {last} ({log}). You are below captain, so claims and releases are not injected; grep the log once for a claim on a path before you edit it.\n\nCross-session channels discovered (audience: frontmatter):\n{chan_lines}")
        emit(context)
        state_file.write_text(norm(new_state))
        return
    # CAPTAINS, ADMIRALS, AND A SESSION WHOSE RANK CANNOT BE TOLD: the whole delta, as before package 8.

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
            "Read each entry in full and give it a disposition without restating it in chat: "
            "act, reply by SendMessage, or dismiss. Say at most one line on what it changes for you. "
            "A reply by SendMessage is mandatory if an entry names your scope, files, or claims, "
            "but never message a stopped session: a message wakes it (check `claude agents --json` first). "
            "This is the 'Cross-session log reading discipline' rule in CLAUDE.md.\n\n"
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
