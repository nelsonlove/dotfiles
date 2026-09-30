#!/usr/bin/env python3
"""contacts-mirror — refresh the 27.20 Contacts mirror in the vault from Apple Contacts.

Ruled by Nelson on 2026-09-30 through the areas admiral ("a plus job", cross-session log 05:50). The macOS ship owns the job; the obsidian ship owns the note shape and the write rules; the people ship names the keys the mirror carries and who is in it. Ships with `status: disabled`.

WHAT IT DOES. It runs the reader command from the config, which prints the cards as JSON (the schema is in README.md next to this file). It matches each mirror note to a card by the note's `source` key (`addressbook://<card id>`), then by the vCard `UID`. For a matched note it rewrites only the keys it owns (the vCard keys listed in the config, and `modified`); every other line of the note stays byte for byte. A note whose card is gone gets `contact-status: missing-from-contacts` and `contact-missing-since: <date>`; the job never deletes, trashes or moves a note, and it removes both keys if the card comes back. A card with no note is only counted: the job creates no note until the people ship's rule allows it (the `create` setting, `none` today).

HOW IT WRITES. Through vault-mcp (`obsidian_read_note` for the `rev`, then `obsidian_write_note` with `overwrite`, `if_rev` and an `idempotency_key`), because the frontmatter tool refuses keys such as `TEL[CELL]`. A `rev_conflict` skips that note for this run. If Obsidian or its bridge is not up, the run skips and says so; it never falls back to plain files in the vault. `--target-dir DIR` writes plain files under DIR instead: that is for a dry run on a /tmp copy of the folder and for the tests, and the job refuses a DIR inside the vault.

WHAT IT LOGS. Counts and short hashes only, never a name, a number or an address: tickle keeps stdout.

Exit codes: 0 done or skipped with a reason; 2 a check failed or bad usage; 3 the reader failed or printed bad JSON. The caller (run.sh) applies the pause and load gates first.

Written for /usr/bin/python3 (3.9), standard library only.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Dict, List, Optional, Tuple

HERE = Path(__file__).resolve().parent
DEFAULT_CONFIG = HERE / "config.json"
VAULT_ROOT = Path(os.environ.get("CM_VAULT_ROOT", str(Path.home() / "obsidian"))).resolve()


class Fail(Exception):
    def __init__(self, code: int, msg: str):
        super().__init__(msg)
        self.code = code


def say(msg: str) -> None:
    print(f"contacts-mirror: {msg}", flush=True)


def short(s: str) -> str:
    """A short, stable, non-reversible tag for a card or note in the log."""
    return hashlib.sha256(s.encode("utf-8")).hexdigest()[:8]


def now_iso() -> str:
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")


def today() -> str:
    return dt.date.today().isoformat()


# ---------------------------------------------------------------- config

def load_config(path: Path) -> dict:
    try:
        cfg = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        raise Fail(2, f"cannot read the config {path}: {e}")
    for k in ("reader", "folder", "keys", "create"):
        if k not in cfg:
            raise Fail(2, f"config {path} has no '{k}'")
    if not isinstance(cfg["reader"], list) or not cfg["reader"]:
        raise Fail(2, "config 'reader' must be a non-empty list (the command and its arguments)")
    if cfg["create"] not in ("none",):
        raise Fail(2, f"config 'create' is '{cfg['create']}'; only 'none' exists until the people ship rules who is in the mirror")
    folder = cfg["folder"]
    if folder.startswith("/") or ".." in Path(folder).parts or folder.startswith("80-89"):
        raise Fail(2, f"config 'folder' must be a vault-relative path outside 80-89: {folder}")
    return cfg


# ---------------------------------------------------------------- cards → owned keys

def _label(raw: Optional[str], default: str) -> str:
    """Contacts labels such as `_$!<Mobile>!$_` or `mobile` → a vCard-style tag such as CELL."""
    if not raw:
        return default
    s = re.sub(r"^_\$!<(.*)>!\$_$", r"\1", raw).strip()
    s = {"mobile": "CELL", "iphone": "CELL", "home": "HOME", "work": "WORK", "main": "MAIN", "other": "OTHER",
         "anniversary": "ANNIVERSARY", "homepage": "HOME", "school": "SCHOOL"}.get(s.lower(), s)
    s = re.sub(r"[^A-Za-z0-9]+", "", s).upper()
    return s or default


def card_keys(card: dict, carry: List[str]) -> Dict[str, str]:
    """The owned keys a card yields, in a stable order, as plain strings. Only keys whose family is in `carry`."""
    out: Dict[str, str] = {}

    def put(key: str, val) -> None:
        if val is None:
            return
        v = str(val).strip()
        if not v:
            return
        family = re.sub(r"(\[.*)$", "", key.split(".")[0])
        if family in carry or key in carry:
            out[key] = v

    n = card.get("n") or {}
    put("FN", card.get("fn"))
    put("N.GN", n.get("given"))
    put("N.MN", n.get("middle"))
    put("N.FN", n.get("family"))
    put("ORG", card.get("org"))
    put("ROLE", card.get("title"))
    for fam, items, default in (("TEL", card.get("tel") or [], "OTHER"), ("EMAIL", card.get("email") or [], "OTHER"),
                                ("URL", card.get("url") or [], "OTHER")):
        seen: Dict[str, int] = {}
        for it in items:
            lab = _label(it.get("label"), default)
            seen[lab] = seen.get(lab, 0) + 1
            tag = lab if seen[lab] == 1 else f"{lab}{seen[lab]}"
            put(f"{fam}[{tag}]", it.get("value"))
    seen = {}
    for a in card.get("adr") or []:
        lab = _label(a.get("label"), "OTHER")
        seen[lab] = seen.get(lab, 0) + 1
        tag = lab if seen[lab] == 1 else f"{lab}{seen[lab]}"
        for part, field in (("STREET", "street"), ("LOCALITY", "locality"), ("REGION", "region"),
                            ("POSTAL", "postal"), ("COUNTRY", "country")):
            put(f"ADR[{tag}].{part}", a.get(field))
    put("BDAY", card.get("bday"))
    for d in card.get("dates") or []:
        if _label(d.get("label"), "") == "ANNIVERSARY":
            put("ANNIVERSARY", d.get("value"))
            break
    return out


def owned_pattern(carry: List[str]) -> re.Pattern:
    fams = "|".join(re.escape(f) for f in sorted(set(k.split(".")[0].split("[")[0] for k in carry)))
    return re.compile(rf"^(?:{fams})(?:\[[A-Z0-9]+\])?(?:\.[A-Z]+)?$")


# ---------------------------------------------------------------- frontmatter, line-preserving

KEY_LINE = re.compile(r"^([^\s#:][^:]*?):(?:\s(.*))?$")
STATUS_KEYS = ("contact-status", "contact-missing-since")


def split_note(text: str) -> Tuple[List[str], str]:
    """Frontmatter lines (without the fences) and the rest of the file, untouched. Raises if there is no frontmatter."""
    if not text.startswith("---\n"):
        raise ValueError("no frontmatter")
    end = text.find("\n---\n", 3)
    if end < 0:
        if text.endswith("\n---"):
            end = len(text) - 4
        else:
            raise ValueError("unclosed frontmatter")
    fm = text[4:end]
    rest = text[end + 1:]
    return (fm.split("\n") if fm else []), rest


def blocks(lines: List[str]) -> List[Tuple[Optional[str], List[str]]]:
    """Group frontmatter lines into (key, lines) blocks; continuation lines (indented, or list items) stay with their key."""
    out: List[Tuple[Optional[str], List[str]]] = []
    for ln in lines:
        m = KEY_LINE.match(ln)
        if m and not ln.startswith((" ", "\t", "-")):
            out.append((m.group(1), [ln]))
        elif out:
            out[-1][1].append(ln)
        else:
            out.append((None, [ln]))
    return out


def unquote(v: str) -> str:
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        inner = v[1:-1]
        return inner.replace("''", "'") if v[0] == "'" else inner.replace('\\"', '"').replace("\\\\", "\\")
    return v


def yaml_value(v: str) -> str:
    """Quote a scalar when YAML would read it as something else or when it has special characters."""
    plain_ok = re.match(r"^[A-Za-z][A-Za-z0-9 ._@,'()&/-]*$", v) and not re.match(
        r"^(?:true|false|yes|no|on|off|null|~)$", v, re.I) and ": " not in v and not v.endswith(":")
    if plain_ok:
        return v
    return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'


def current_values(bl: List[Tuple[Optional[str], List[str]]]) -> Dict[str, str]:
    vals = {}
    for k, ls in bl:
        if k is None:
            continue
        m = KEY_LINE.match(ls[0])
        vals[k] = unquote(m.group(2) or "") if len(ls) == 1 else "\n".join(ls)
    return vals


def rewrite(text: str, want: Dict[str, str], owned: re.Pattern, status: Optional[Dict[str, str]],
            stamp: str) -> Tuple[str, List[str]]:
    """Return (new text, changed keys). Only owned keys, the two status keys and `modified` may change; every other
    frontmatter line and the whole body stay byte for byte. An unchanged owned key keeps its line as it was."""
    lines, rest = split_note(text)
    bl = blocks(lines)
    cur = current_values(bl)
    changed: List[str] = []
    out: List[Tuple[Optional[str], List[str]]] = []
    placed = set()
    anchor = None  # index in `out` after which new owned keys go
    for k, ls in bl:
        if k is not None and owned.match(k):
            if k in want:
                if cur.get(k) != want[k]:
                    ls = [f"{k}: {yaml_value(want[k])}"]
                    changed.append(k)
                placed.add(k)
                out.append((k, ls))
                anchor = len(out)
            else:
                changed.append(k)  # the card lost this field: drop the key
            continue
        if k in STATUS_KEYS:
            if status is not None and k in status:
                if cur.get(k) != status[k]:
                    ls = [f"{k}: {yaml_value(status[k])}"]
                    changed.append(k)
                placed.add(k)
                out.append((k, ls))
            else:
                changed.append(k)
            continue
        out.append((k, ls))
        if k == "aliases" and anchor is None:
            anchor = len(out)
    new_owned = [(k, [f"{k}: {yaml_value(v)}"]) for k, v in want.items() if k not in placed]
    if new_owned:
        changed.extend(k for k, _ in new_owned)
        pos = anchor if anchor is not None else len(out)
        out[pos:pos] = new_owned
    if status:
        new_status = [(k, [f"{k}: {yaml_value(v)}"]) for k, v in status.items() if k not in placed]
        if new_status:
            changed.extend(k for k, _ in new_status)
            out.extend(new_status)
    if changed:
        for i, (k, ls) in enumerate(out):
            if k == "modified":
                out[i] = (k, [f"modified: {stamp}"])
                break
    new_lines = [ln for _, ls in out for ln in ls]
    return "---\n" + "\n".join(new_lines) + ("\n" if new_lines else "") + rest, changed


# ---------------------------------------------------------------- stores

class DirStore:
    """Plain files under a root that is NOT the vault: dry runs on a /tmp copy, and tests."""

    def __init__(self, root: Path, folder: str):
        self.root = root.resolve()
        try:
            self.root.relative_to(VAULT_ROOT)
        except ValueError:
            pass
        else:
            raise Fail(2, f"--target-dir {self.root} is inside the vault; the vault is written only through vault-mcp")
        self.folder = folder

    def list_notes(self) -> List[str]:
        d = self.root / self.folder
        if not d.is_dir():
            raise Fail(2, f"the mirror folder is missing under {self.root}")
        return sorted(f"{self.folder}/{p.name}" for p in d.iterdir() if p.suffix == ".md" and p.is_file())

    def read(self, rel: str) -> Tuple[str, Optional[int]]:
        return (self.root / rel).read_text(encoding="utf-8"), None

    def write(self, rel: str, text: str, rev: Optional[int]) -> str:
        p = self.root / rel
        tmp = p.with_name(f".{p.name}.cm-tmp")
        tmp.write_text(text, encoding="utf-8")
        os.replace(tmp, p)
        return "ok"


class McpStore:
    """vault-mcp through its stdio bridge (MCP JSON-RPC 2.0)."""

    def __init__(self, folder: str, bridge: List[str], vault: str):
        self.folder = folder
        try:
            self.proc = subprocess.Popen(bridge + ["--vault", vault], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                         stderr=subprocess.PIPE, text=True, bufsize=1)
        except OSError as e:
            raise Fail(0, f"SKIPPED — cannot start the vault-mcp bridge ({e}); Obsidian must be running")
        self.n = 0
        try:
            self._call("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                      "clientInfo": {"name": "contacts-mirror", "version": "1"}})
        except Fail as e:
            raise Fail(0, f"SKIPPED — vault-mcp is not answering ({e}); Obsidian must be running")
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def _send(self, msg: dict) -> None:
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()

    def _call(self, method: str, params: dict) -> dict:
        self.n += 1
        self._send({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params})
        assert self.proc.stdout is not None
        while True:
            line = self.proc.stdout.readline()
            if not line:
                err = self.proc.stderr.read() if self.proc.stderr else ""
                raise Fail(2, f"vault-mcp bridge closed: {err.strip()[:200]}")
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if msg.get("id") == self.n:
                if "error" in msg:
                    raise Fail(2, f"vault-mcp error: {str(msg['error'])[:200]}")
                return msg.get("result") or {}

    def _tool(self, name: str, args: dict) -> Tuple[bool, str]:
        res = self._call("tools/call", {"name": name, "arguments": args})
        text = "".join(c.get("text", "") for c in res.get("content") or [] if c.get("type") == "text")
        return bool(res.get("isError")), text

    def list_notes(self) -> List[str]:
        paths: List[str] = []
        offset = 0
        while True:
            err, text = self._tool("obsidian_list_notes", {"subdir": self.folder, "limit": 500, "offset": offset})
            if err:
                raise Fail(2, f"cannot list the mirror folder: {text[:200]}")
            try:
                data = json.loads(text)
            except json.JSONDecodeError:
                raise Fail(2, "obsidian_list_notes returned something that is not JSON")
            items = data.get("notes") or []
            paths += [i.get("path") for i in items if isinstance(i, dict)]
            if not data.get("has_more") or not items:
                break
            offset += len(items)
        return sorted(p for p in paths if isinstance(p, str) and p.startswith(self.folder + "/")
                      and "/" not in p[len(self.folder) + 1:] and p.endswith(".md"))

    def read(self, rel: str) -> Tuple[str, Optional[int]]:
        err, text = self._tool("obsidian_read_note", {"path": rel})
        if err:
            raise Fail(2, f"cannot read note {short(rel)}: {text[:120]}")
        data = json.loads(text)
        return data["content"], data.get("rev")

    def write(self, rel: str, text: str, rev: Optional[int]) -> str:
        if rev is None:
            raise Fail(2, "vault-mcp gave no rev; refusing an unconditional overwrite")
        err, out = self._tool("obsidian_write_note", {
            "path": rel, "content": text, "overwrite": True, "if_rev": rev,
            "idempotency_key": f"contacts-mirror-{uuid.uuid4()}",
            "intent": "contacts-mirror: refresh the vCard keys from Apple Contacts (Nelson's 'a plus job', 2026-09-30)"})
        if err:
            return "conflict" if "rev_conflict" in out else "error"
        return "ok"

    def close(self) -> None:
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()


# ---------------------------------------------------------------- the run

def read_cards(cmd: List[str], timeout: int) -> List[dict]:
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise Fail(3, f"the reader could not run: {type(e).__name__}")
    if p.returncode != 0:
        raise Fail(3, f"the reader exited {p.returncode}: {p.stderr.strip()[:200]}")
    try:
        data = json.loads(p.stdout)
    except json.JSONDecodeError:
        raise Fail(3, "the reader printed something that is not JSON")
    cards = data.get("cards") if isinstance(data, dict) else None
    if not isinstance(cards, list) or not all(isinstance(c, dict) and c.get("id") for c in cards):
        raise Fail(3, "the reader's JSON has no 'cards' list of objects with an 'id'")
    return cards


def note_ids(text: str) -> Tuple[Optional[str], Optional[str]]:
    try:
        lines, _ = split_note(text)
    except ValueError:
        return None, None
    vals = current_values(blocks(lines))
    src = vals.get("source", "")
    src = src[len("addressbook://"):] if src.startswith("addressbook://") else None
    return (src or None), (vals.get("UID") or None)


def run(args) -> int:
    cfg = load_config(Path(args.config))
    carry: List[str] = cfg["keys"]
    owned = owned_pattern(carry)
    folder = cfg["folder"]
    cards = read_cards(args.reader or cfg["reader"], int(cfg.get("reader_timeout", 120)))
    by_id = {c["id"]: c for c in cards}
    by_uid = {c["uid"]: c for c in cards if c.get("uid")}
    say(f"reader: {len(cards)} cards")

    if args.target_dir:
        store = DirStore(Path(args.target_dir), folder)
    else:
        store = McpStore(folder, cfg.get("bridge", ["node", str(Path.home() / ".claude/vault-mcp/bridge.mjs")]),
                         cfg.get("vault", "obsidian"))
    counts = {"updated": 0, "unchanged": 0, "missing": 0, "unmatched": 0, "conflict": 0, "error": 0, "skipped": 0}
    matched_ids = set()
    shown = 0
    stamp = now_iso()
    try:
        for rel in store.list_notes():
            name = rel.rsplit("/", 1)[-1]
            if name == f"{folder.rsplit('/', 1)[-1]}.md":
                continue  # the folder note
            text, rev = store.read(rel)
            src, vuid = note_ids(text)
            card = by_id.get(src) if src else None
            if card is None and vuid:
                card = by_uid.get(vuid)
            if card is None and not src and not vuid:
                counts["unmatched"] += 1
                say(f"note {short(rel)}: no source and no UID; left alone")
                continue
            if card is None:
                status = {"contact-status": "missing-from-contacts"}
                try:
                    lines, _ = split_note(text)
                    since = current_values(blocks(lines)).get("contact-missing-since")
                except ValueError:
                    since = None
                status["contact-missing-since"] = since or today()
                want = {k: v for k, v in current_values(blocks(split_note(text)[0])).items() if owned.match(k)}
            else:
                matched_ids.add(card["id"])
                status = None
                want = card_keys(card, carry)
            try:
                new, changed = rewrite(text, want, owned, status, stamp)
            except ValueError:
                counts["skipped"] += 1
                say(f"note {short(rel)}: frontmatter unreadable; left alone")
                continue
            if card is None:
                counts["missing"] += 1
            if not changed:
                if card is not None:
                    counts["unchanged"] += 1
                continue
            if args.show and shown < args.show:
                shown += 1
                import difflib
                sys.stdout.writelines(difflib.unified_diff(text.splitlines(True), new.splitlines(True),
                                                           f"a/{rel}", f"b/{rel}", n=0))
            if args.plan:
                counts["updated"] += card is not None
                continue
            result = store.write(rel, new, rev)
            if result == "ok":
                counts["updated"] += card is not None
            else:
                counts[result] += 1
                say(f"note {short(rel)}: write {result}; left for the next run")
    finally:
        if isinstance(store, McpStore):
            store.close()
    counts["new"] = len(set(by_id) - matched_ids)
    say("counts: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    if counts["new"]:
        say(f"{counts['new']} cards have no note; none created (create = {cfg['create']}, until the people ship rules)")
    return 2 if counts["error"] else 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--config", default=str(DEFAULT_CONFIG))
    ap.add_argument("--target-dir", help="write plain files under this root (a /tmp copy), never the vault")
    ap.add_argument("--reader", nargs="+", help="override the config's reader command (tests, dry runs)")
    ap.add_argument("--plan", action="store_true", help="change nothing; count and show what would change")
    ap.add_argument("--show", type=int, default=0, help="print the diff of the first N changed notes (terminal only)")
    args = ap.parse_args(argv)
    try:
        return run(args)
    except Fail as e:
        (say if e.code == 0 else lambda m: print(f"contacts-mirror: FAILED — {m}", file=sys.stderr))(str(e))
        return e.code


if __name__ == "__main__":
    sys.exit(main())
