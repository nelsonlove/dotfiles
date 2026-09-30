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
# A RULING, by its heading: the kind marker after the author is "— ruling" (em dash, en dash or hyphen; a space is needed before a hyphen only), singular or plural, at the end, before a colon ("— ruling: Nelson …"), before a note in brackets ("- ruling (relayed)"), or combined ("— ruling and release in one"); or "ruling executed:". Measured on the real log 2026-09-29: 115 end in "— ruling", 1 has "— ruling:", 0 have "ruling executed:", and no heading whose kind names a ruling is missed. The word "ruling" elsewhere is not the marker: a claim "— claim: for Nelson's … ruling" is a claim. The test's population case fails on any heading whose kind names a ruling and is not read as one, so a new form is caught there rather than dropped in silence.
# AN AUDIENCE MARK after the kind ("— ruling · ships: MA", "— ruling · fleet", "— ruling · for: [C0-PE] personal") is a ruling too: measured 2026-09-30, five marked rulings in the real log ("— ruling · ships: MA, CC" and the like) were read as NOT rulings by the pattern before this, so no session below captain was shown them.
RULING = re.compile(r"(?:\s?[—–]|(?:^|\s)-)\s*rulings?(?:\s*(?::|\(|·|$)|\s+and\s)|\bruling executed\s*:", re.I)
RULINGS_MAX_CHARS = 3000

# THE RANK is read the way the fleet scripts read it, from the one table (claude/bin/_fleet-ranks.sh, sourced, never copied): the job state's `template` first, through rank_of_agent; then the session's name in `claude agents --json --all`, through rank_of_name. If neither gives a rank, the session gets the WHOLE delta: failing toward more reading is safe, and toward less is not.
FLEET_RANKS = Path(__file__).resolve().parent.parent / "bin" / "_fleet-ranks.sh"
JOBS_DIR = Path.home() / ".claude/jobs"


def plural(n, word):
    return f"{n} {word}" + ("" if n == 1 else "s")


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
    name = listing_name(session_id)
    if name:
        return rank_via_table("rank_of_name", name)
    return None


_LISTING = {}


def listing_name(session_id):
    """The session's name in `claude agents --json --all`, asked once per run."""
    if session_id not in _LISTING:
        short = session_id[:8]
        try:
            rows = json.loads(subprocess.run(["claude", "agents", "--json", "--all"], capture_output=True, text=True, timeout=3).stdout or "[]")
        except Exception:
            rows = []
        name = ""
        for row in rows if isinstance(rows, list) else []:
            if session_id in (row.get("sessionId"), row.get("id")) or short == row.get("id"):
                name = row.get("name") or ""
                if name:
                    break
        _LISTING[session_id] = name
    return _LISTING[session_id]


# THE AUDIENCE FILTER (Nelson, 2026-09-30, "a for all", on `01.65 Operator's console/Decide who sees each ruling — the filer and its chain by default.md`). BELOW CAPTAIN ONLY: captains, admirals and a session whose rank cannot be told keep the full delta. A ruling's heading may carry its audience after the kind, as ` · for: <label>` (one label per segment), ` · ships: <codes>` (comma-separated; `fleet` among them means the fleet) or ` · fleet`; the grammar is in `marks` below. A session below captain is shown a ruling when:
#   * `for:` names it, or a session whose chain UP includes it (the chain is the notebook entries' `reports-to`, read now); a cycle or a missing link means "not shown by `for:`", and the other rules still apply;
#   * `ships:` holds its own ship code;
#   * it says `fleet`;
#   * it carries NO mark at all (question 1, A: fail-open, so a writer's slip costs noise and never a missed ruling).
# `[L0]` (question 5, A: the one-task rank) is narrower: `ships:` marks do NOT reach it; `for:` its own chain, a ruling whose text names it, `fleet` and no-mark still do.
# LABELS, NEVER IDS (question 2, A). A session's labels are its current name, its registry `formerNames`, and every label the rename ledger joins to it (below). If this session's own label cannot be told at all, NOTHING is filtered: failing toward more reading is safe.
# A RULING THAT NAMES A QUEUE ITEM (the note's rule 1: it reaches the item's filer and its chain) is NOT read from the item here. Measured on the real log 2026-09-30: of 138 rulings, 3 carry any wikilink and none of those names an `Open items` note; items are named in prose. So such a ruling falls under fail-open (it carries no mark) and nothing is hidden; reading the item's first `session:` is proposed, not built.
SESSIONS_DIR = Path.home() / ".claude/sessions"
AGENTS_DIR = VAULT / "00-09 System" / "03 Agents"
NOTEBOOK_ROOTS = Path(__file__).resolve().parent.parent / "lib" / "notebook-roots.sh"
MARK_SPLIT = re.compile(r"\s·\s")
BARE = re.compile(r"^\[[^\]]*\]\s*")
SHIP_CODE = re.compile(r"^[A-Za-z]{1,4}$")  # the code shape `ship_of_name` accepts
# THE RENAME LEDGER, the exact lines `claude/bin/rename-notebook.sh` writes: a heading `## <stamp> · <new name> — notebook entry renamed to match the session's name` (or `— notebook entry's keys repaired after an interrupted rename`), and in the body "(sessionId <full id>)"; a rename's body also reads "Renamed `<old file>` to `<new file>`". The heading's name is a LABEL the session held; the old file's name carries only the bare name (no rank code), since the entry's filename drops it.
RENAME_HEAD = re.compile(r"^## \S+ · (.+?) — notebook entry(?: renamed to match the session's name|'s keys repaired after an interrupted rename)\s*$")
RENAME_ID = re.compile(r"\(sessionId ([0-9A-Fa-f-]{36})\)")
RENAME_OLD = re.compile(r"Renamed `([^`]+)` to `")
ENTRY_STAMP = re.compile(r"\d{4}-\d{2}-\d{2}T\d{4}")
# THE BUDGET. The hook runs under the 15-second SessionStart timeout in settings.json, and a killed hook shows NO rulings. So the notebook read is given 3 seconds, and a read that fails or times out turns `for:` into fail-open (shown), never into "not shown".
LINES_TIMEOUT = 3


def nl(label):
    """One form of a label for comparison: quotes and backticks off the ends, spaces collapsed, case folded. A writer's `for: \`[C1-CC] Plugins\`` still names `[C1-CC] plugins`."""
    return re.sub(r"\s+", " ", (label or "").strip().strip("`'\"").strip()).casefold()


def bare(label):
    return BARE.sub("", nl(label)).strip()


def ship_of(label):
    """The ship code, from `ship_of_name` in claude/bin/_fleet-ranks.sh (sourced, never copied); None when there is none."""
    try:
        out = subprocess.run(["bash", "-c", '. "$1" >/dev/null 2>&1 || exit 9; ship_of_name "$2"', "_", str(FLEET_RANKS), label or ""],
                             capture_output=True, text=True, timeout=3).stdout.strip()
    except Exception:
        return None
    return out.upper() or None


def marks(heading):
    """The audience marks, by the grammar agreed with the obsidian ship (2026-09-30): ` · `-separated segments after the kind; `fleet` (canonical) or `ships: fleet`; `ships: PE, HH` (comma-separated codes, spaces optional, upper-cased); `for: <label>`, ONE label per segment, repeated for several (no comma split: a label may hold a comma). Segments combine as a union. Any other segment is ignored, so a heading whose only segment is a typo (`· ship: PE`) carries no mark and goes to everyone: fail-open holds for a slip. A `ships:` value holding anything that is not a code (`ships: MA (dotfiles)`, `ships: MA and CC`) is a slip inside a known key, and it too goes to everyone: returned as fleet. Returns (for-labels, ship codes, fleet?)."""
    fors, ships, fleet = [], set(), False
    for seg in MARK_SPLIT.split(heading)[2:]:
        seg = seg.strip()
        low = seg.lower()
        if low == "fleet":
            fleet = True
        elif low.startswith("for:"):
            label = seg[4:].strip()
            if label:
                fors.append(label)
        elif low.startswith("ships:"):
            for code in seg[6:].split(","):
                code = code.strip().strip("`'\"").strip()
                if code.lower() == "fleet":
                    fleet = True
                elif SHIP_CODE.match(code):
                    ships.add(code.upper())
                elif code:
                    fleet = True
    return fors, ships, fleet


def registry_rows():
    """Every row of the session registry (`~/.claude/sessions/<pid>.json`) that parses, read once."""
    rows = []
    try:
        files = list(SESSIONS_DIR.glob("*.json"))
    except Exception:
        files = []
    for f in files:
        try:
            d = json.loads(f.read_text())
            mt = f.stat().st_mtime
        except Exception:
            continue
        if isinstance(d, dict):
            rows.append((d, mt))
    return rows


class Aliases:
    """Which labels name one session: union-find over normalised labels, from the registry's `formerNames` and the rename ledger, joined through the sessionId. A chain of renames (A to B, then B to C) lands in one set, because each ledger line of one id joins its label to the rest."""

    def __init__(self, log_entries, rows):
        self.parent = {}
        self.old_bare = {}  # bare name of a pre-rename file -> {(ship, root label)}
        by_id = {}
        olds = []
        for _, e in log_entries:
            head, _, body = e.partition("\n")
            m = RENAME_HEAD.match(head)
            i = RENAME_ID.search(body)
            if not (m and i):
                continue
            label = m.group(1).strip()
            by_id.setdefault(i.group(1).lower(), []).append(nl(label))
            o = RENAME_OLD.search(body)
            if o:
                name = re.sub(r"\.md$", "", o.group(1))
                name = ENTRY_STAMP.split(name, 1)[-1].strip() if ENTRY_STAMP.search(name) else ""
                if name:
                    olds.append((nl(name), label))
        for labels in by_id.values():
            for l in labels[1:]:
                self.union(labels[0], l)
        for d, _ in rows:
            name = nl(d.get("name"))
            if not name:
                continue
            self.find(name)
            for x in d.get("formerNames") or []:
                if isinstance(x, dict) and x.get("name"):
                    self.union(name, nl(x["name"]))
                    old = str(x.get("sessionId") or "").lower()
                    if old in by_id:
                        self.union(name, by_id[old][0])
            sid = str(d.get("sessionId") or "").lower()
            if sid in by_id:
                self.union(name, by_id[sid][0])
        # A BARE PRE-RENAME NAME matches only a label on the SAME SHIP as the renamed session, so `[L0-MA] dotfiles` is not taken for a CC session once called `dotfiles`. The ship is read off the label text (the `[X0-SS]` shape) here, not through the table, to keep this cheap; it is the same pattern.
        for name, label in olds:
            self.old_bare.setdefault(name, set()).add((self._ship(label), nl(label)))

    @staticmethod
    def _ship(label):
        m = re.match(r"^\[[A-Za-z][0-9]-([A-Za-z]{1,4})\]", (label or "").strip().strip("`'\""))
        return m.group(1).upper() if m else None

    def find(self, x):
        self.parent.setdefault(x, x)
        root = x
        while self.parent[root] != root:
            root = self.parent[root]
        while self.parent[x] != root:
            self.parent[x], x = root, self.parent[x]
        return root

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[rb] = ra

    def root(self, label):
        """The set a (normalised) label belongs to: its own set, or, by a bare pre-rename name, the renamed session's set on the same ship."""
        if label in self.parent:
            return self.find(label)
        for ship, renamed in self.old_bare.get(bare(label), ()):
            if ship and ship == self._ship(label):
                return self.find(renamed)
        return label

    def labels_of(self, label):
        r = self.root(label)
        return {l for l in list(self.parent) if self.find(l) == r} | {label}


def reporting_lines():
    """label -> (stamp, reports-to), normalised labels, from every notebook entry. Entries are listed by `notebook_entry_files_of` in claude/lib/notebook-roots.sh, sourced, so the two roots and the one-month-folder depth are that library's. Returns None when the list cannot be read (failure, timeout, or no entries at all), which the caller turns into fail-open."""
    try:
        res = subprocess.run(["bash", "-c", '. "$1" || exit 9; notebook_entry_files_of "$2" 0 "$3" 0', "_", str(NOTEBOOK_ROOTS),
                              str(AGENTS_DIR / "03.04 Records" / "Agent notebook"), str(AGENTS_DIR / "03.09 Archive" / "Agent notebook")],
                             capture_output=True, text=True, timeout=LINES_TIMEOUT)
    except Exception:
        return None
    files = [f for f in res.stdout.splitlines() if f]
    if res.returncode != 0 or not files:
        return None
    rows = []
    for f in files:
        k = fm_keys(f, ("session", "reports-to"))
        if k.get("session"):
            m = ENTRY_STAMP.search(Path(f).name)
            rows.append((nl(k["session"]), m.group(0) if m else "", nl(k.get("reports-to"))))
    return rows


def fm_keys(path, keys):
    """`roster_value`'s reading (claude/lib/session-roster.sh) for a few keys: a CLOSED block, column zero, a key stated twice reads as nothing, a quoted value taken whole to its first closing quote, only an unquoted one losing a trailing ` # comment`."""
    try:
        with open(path, errors="replace") as f:
            head = f.read(8192)
    except OSError:
        return {}
    lines = head.split("\n")
    if not lines or lines[0].rstrip("\r \t") != "---":
        return {}
    block = []
    for ln in lines[1:]:
        if ln.rstrip("\r \t") == "---":
            break
        block.append(ln.rstrip("\r"))
    else:
        return {}
    out = {}
    for k in keys:
        hits = [ln for ln in block if re.match(re.escape(k) + r"[ \t]*:", ln)]
        if len(hits) != 1:
            continue
        v = re.sub(re.escape(k) + r"[ \t]*:[ \t]*", "", hits[0], count=1).rstrip()
        if v.startswith('"') and '"' in v[1:]:
            v = v[1:].split('"', 1)[0]
        elif v.startswith("'") and "'" in v[1:]:
            v = v[1:].split("'", 1)[0]
        else:
            v = re.sub(r"[ \t]+#.*$", "", v).rstrip()
        if v:
            out[k] = v
    return out


class Audience:
    """Who this session is, for the filter: its labels, its ship, its rank. The aliases and the reporting lines are read only when a ruling needs them, once, and every lookup is cached."""

    def __init__(self, session_id, rank, log_entries):
        self.rank = rank
        self.entries = log_entries
        self.rows = registry_rows()
        self._aliases = None
        self._lines = None  # root -> [(stamp, reports-to)], or False when unreadable
        self._up = {}
        self._reach = {}
        # THE NEWEST registry row for this id wins (a resumed session can leave an older pid file behind).
        mine = sorted(((d, mt) for d, mt in self.rows if str(d.get("sessionId") or "").lower() == session_id.lower()),
                      key=lambda r: (r[0].get("updatedAt") or 0, r[1]))
        name, former = "", []
        if mine:
            d = mine[-1][0]
            name = d.get("name") or ""
            former = [x["name"] for x in d.get("formerNames") or [] if isinstance(x, dict) and x.get("name")]
        if not name:
            name = listing_name(session_id) or ""
        self.name = name
        self.own_raw = [l for l in [name] + former if l]
        self.ship = ship_of(name) if name else None
        self._own = None

    @property
    def known(self):
        return bool(self.name)

    def aliases(self):
        if self._aliases is None:
            self._aliases = Aliases(self.entries, self.rows)
        return self._aliases

    def own_roots(self):
        if self._own is None:
            a = self.aliases()
            self._own = {a.root(nl(l)) for l in self.own_raw}
        return self._own

    def is_me(self, label):
        return self.aliases().root(nl(label)) in self.own_roots()

    def lines(self):
        if self._lines is None:
            rows = reporting_lines()
            if rows is None:
                self._lines = False
            else:
                a = self.aliases()
                self._lines = {}
                for label, stamp, r in rows:
                    self._lines.setdefault(a.root(label), []).append((stamp, r))
        return self._lines

    def known_label(self, label):
        """A `for:` label the fleet has any record of: a notebook entry, a registry row or a rename. A label with none is a writer's slip, shown to everyone."""
        a = self.aliases()
        r = a.root(nl(label))
        lines = self.lines()
        return r in a.parent or (lines is not False and r in lines)

    def reports_to(self, label):
        """The superior's normalised label from the NEWEST entry of this session (any of its labels) that states one; entries with no `reports-to` are skipped. Two newest entries that disagree read as a broken link (None)."""
        r = self.aliases().root(nl(label))
        if r not in self._up:
            cands = [(s, v) for s, v in (self.lines() or {}).get(r, []) if v]
            up = None
            if cands:
                top = max(s for s, _ in cands)
                vals = {v for s, v in cands if s == top}
                up = vals.pop() if len(vals) == 1 else None
            self._up[r] = up
        return self._up[r]

    def chain_reaches_me(self, label):
        """True when `label` is this session, or a session whose chain UP includes it. A cycle or a missing link ends the walk with False."""
        if label in self._reach:
            return self._reach[label]
        seen, cur, ok = set(), label, False
        for _ in range(32):
            if self.is_me(cur):
                ok = True
                break
            root = self.aliases().root(nl(cur))
            if root in seen:
                break
            seen.add(root)
            nxt = self.reports_to(cur)
            if not nxt:
                break
            cur = nxt
        self._reach[label] = ok
        return ok

    def names_me(self, entry):
        """The BODY names one of this session's labels, as a whole label (not inside a longer one), case-blind. The heading is left out, so a ruling this session wrote or relayed does not count as naming it."""
        body = entry.split("\n", 1)[1] if "\n" in entry else ""
        labels = set()
        for l in self.own_raw:
            labels |= self.aliases().labels_of(self.aliases().root(nl(l))) | {nl(l)}
        return any(l and re.search(r"(?<![\w\]-])" + re.escape(l) + r"(?![\w-])", body, re.I) for l in labels)

    def shows(self, entry):
        heading = entry.split("\n", 1)[0]
        fors, ships, fleet = marks(heading)
        if fleet or not (fors or ships):
            return True
        if self.rank < 3 and ships:
            # A session whose name carries no ship code cannot be matched by `ships:`, so it is shown them: fail toward more reading.
            if not self.ship or self.ship in ships:
                return True
        if fors:
            if self.lines() is False:
                return True  # the notebook could not be read: `for:` fails open
            for x in fors:
                if not self.known_label(x) or self.chain_reaches_me(x):
                    return True
        if self.rank >= 3:
            return self.names_me(entry)
        return False


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
    first_run = not last
    if not last:
        last = (datetime.now() - timedelta(hours=FIRST_RUN_WINDOW_HOURS)).strftime(
            "%Y-%m-%dT%H:%M"
        )

    unread = [(s, e) for s, e in entries if norm(s) > norm(last)]

    # The rank is looked up only when there is something to show: it costs a bash and, for some sessions, a `claude agents` listing.
    rank = session_rank(session_id) if unread else None
    if rank is not None and rank >= 1:
        # BELOW CAPTAIN: rulings only. THE STAMP, on a later run: it advances past every ruling shown, and past the claims and releases around them, which are not meant to be read below captain; it never passes a ruling that was not shown. With rulings left over the cap, it stops just below the first of them, so that ruling (and anything tied with it) comes back next start.
        # ON A FIRST RUN (no stamp file for this session id; the captain's word on the #99 follow-up) the rule differs ON PURPOSE: the NEWEST rulings are shown, newest first, up to the cap (the newest stamp group kept whole), and the stamp goes to the newest ruling, so the older rulings of the 48-hour window are passed and never paged later. The note says so. On both runs the stamp is clamped to now, so a ruling stamped in the future (a harness-clock stamp runs a day ahead after 20:00 local) cannot hide the rulings logged before it.
        unread.sort(key=lambda pair: norm(pair[0]))
        # THE AUDIENCE FILTER, then the stamp rules unchanged over what it leaves. A ruling the filter drops is NOT FOR this session, so the stamp may pass it exactly as it passes a claim; a ruling it keeps is treated exactly as every ruling was before, so the stamp never passes one of those unshown (the cap floor below is taken from the kept rulings only). If this session's own label cannot be told, nothing is dropped.
        audience = Audience(session_id, rank, entries)
        all_rulings = [(s, e) for s, e in unread if is_ruling(e.split("\n", 1)[0])]
        rulings = [(s, e) for s, e in all_rulings if not audience.known or audience.shows(e)]
        dropped = len(all_rulings) - len(rulings)
        if first_run and rulings:
            shown, used = [], 0
            top = norm(rulings[-1][0])
            for s_, e_ in reversed(rulings):
                if shown and used + len(e_) > RULINGS_MAX_CHARS and norm(s_) != top:
                    break
                shown.append((s_, e_)); used += len(e_)
            older = len(rulings) - len(shown)
            left = []
            note = (f"[This session's first start: the newest {plural(len(shown), 'ruling')} {'is' if len(shown) == 1 else 'are'} shown, newest first. {plural(older, 'older ruling')} from the last {FIRST_RUN_WINDOW_HOURS} hours {'is' if older == 1 else 'are'} not shown and will not come back; read them in the file if your work needs them.]\n\n" if older else "")
            new_state = top
        else:
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
            note = (f"[{plural(len(left), 'more ruling')} not shown: read them in the file now; they will also come back at the next session start]\n\n" if left else "")
        # On either run, the stamp is clamped to now: a ruling stamped in the future cannot carry it past the rulings logged before that moment. The future-stamped ruling itself is shown again at each start until its time comes, which errs toward more reading.
        new_state = min(new_state, datetime.now().strftime("%Y-%m-%dT%H:%M"))
        chan_lines = "\n".join(f"- {c}" for c in channel_index()) or f"- {log}"
        if not audience.known:
            audience_text = "Your session's name could not be read, so the audience filter is off and every ruling is shown."
        elif rank >= 3:
            audience_text = ("You are a lieutenant, the one-task rank, so you are shown only: rulings marked `for:` you (or a session under you) or that name you; rulings marked `fleet` (fleet-wide); and rulings with no audience mark (a writer's slip is shown to everyone rather than hidden). `ships:` marks do not reach you: your brief carries the rulings for your task.")
        else:
            audience_text = ("You are shown the rulings marked `for:` you or a session under you, `ships:` your ship, or `fleet`, and every ruling with no audience mark (a writer's slip is shown to everyone rather than hidden).")
        if dropped:
            audience_text += f" {plural(dropped, 'ruling')} for other sessions or ships {'was' if dropped == 1 else 'were'} left out."
        if shown:
            context = (
                f"UNREAD CROSS-SESSION LOG: RULINGS ONLY ({log}):\n"
                "You are below captain, so since Nelson's ruling of 2026-09-29 you read the RULINGS; claims and releases are left out. "
                "Before you edit a file, grep the log once for a claim on that path, and honour it. Do not start a Monitor on the log. "
                "Read each ruling in full and give it a disposition without restating it in chat. Say at most one line on what it changes for you. "
                "This is the 'Cross-session log reading discipline' rule in CLAUDE.md.\n"
                + audience_text + "\n\n"
                + "\n\n".join(e_ for _, e_ in shown) + "\n\n" + note
                + f"Cross-session channels discovered (audience: frontmatter):\n{chan_lines}"
            )
        else:
            context = (f"Cross-session log: no new rulings since {last} ({log}). You are below captain, so claims and releases are not injected; grep the log once for a claim on a path before you edit it. {audience_text}\n\nCross-session channels discovered (audience: frontmatter):\n{chan_lines}")
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
