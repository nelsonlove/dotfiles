"""Tests for contacts-mirror. Made-up people and cards only: no real contact data anywhere in this file."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
JOB = HERE.parent
sys.path.insert(0, str(JOB))
import mirror  # noqa: E402

FOLDER = "20-29 People/27 PRM/27.20 Contacts"
CARRY = ["FN", "N.GN", "N.MN", "N.FN", "ORG", "ROLE", "TEL", "EMAIL", "ADR", "URL", "BDAY", "ANNIVERSARY"]

# A note in the shape the mirror has today, with everything the job must not touch: two list styles, both quote styles,
# keys from elsewhere, a vCard UID and VERSION, and a body with hand-written sections.
ADA = textwrap.dedent('''\
    ---
    title: Ada Example
    uid: 00000000-0000-7000-8000-000000000001
    created: 2026-07-19T00:00:00
    modified: 2026-07-19T00:00:00
    tags:
      - person
    aliases:
    - Ada Example
    FN: Ada Example
    N.GN: Ada
    N.FN: Example
    TEL[CELL]: (555) 010-0100
    EMAIL[HOME]: ada@example.invalid
    ADR[HOME].POSTAL: "00001"
    UID: urn:uuid:11111111-2222-3333-4444-555555555555
    VERSION: '4.0'
    source: addressbook://AAAA-0001:ABPerson
    messages: 12
    last-contacted: 2025-01-02
    photos-faces: 3
    ---

    # Ada Example

    ## Notes

    Hand-written line: keep me.

    ## From messages

    - something the job must never touch
    ''')

ADA_CARD = {"id": "AAAA-0001:ABPerson", "fn": "Ada Example", "n": {"given": "Ada", "family": "Example"},
            "tel": [{"label": "_$!<Mobile>!$_", "value": "(555) 010-0100"}],
            "email": [{"label": "home", "value": "ada@example.invalid"}],
            "adr": [{"label": "home", "postal": "00001"}]}


def owned():
    return mirror.owned_pattern(CARRY)


class Keys(unittest.TestCase):
    def test_labels_and_numbering(self):
        k = mirror.card_keys({"id": "x", "tel": [{"label": "_$!<Mobile>!$_", "value": "1"}, {"label": "mobile", "value": "2"},
                                                  {"label": None, "value": "3"}]}, CARRY)
        self.assertEqual(k, {"TEL[CELL]": "1", "TEL[CELL2]": "2", "TEL[OTHER]": "3"})

    def test_anniversary_and_bday(self):
        k = mirror.card_keys({"id": "x", "bday": "--03-04", "dates": [{"label": "_$!<Other>!$_", "value": "2000-01-01"},
                                                                      {"label": "_$!<Anniversary>!$_", "value": "2010-05-06"}]}, CARRY)
        self.assertEqual(k, {"BDAY": "--03-04", "ANNIVERSARY": "2010-05-06"})

    def test_carry_limits_families(self):
        k = mirror.card_keys(ADA_CARD, ["FN"])
        self.assertEqual(k, {"FN": "Ada Example"})

    def test_owned_pattern(self):
        p = owned()
        for key in ("FN", "N.GN", "TEL[CELL2]", "ADR[HOME].POSTAL", "BDAY", "ANNIVERSARY", "URL[HOME]"):
            self.assertTrue(p.match(key), key)
        for key in ("UID", "VERSION", "source", "uid", "tags", "messages", "last-contacted", "photos-faces", "title", "modified"):
            self.assertFalse(p.match(key), key)


class Rewrite(unittest.TestCase):
    STAMP = "2026-10-01T04:20:00-04:00"

    def test_unchanged_card_changes_nothing(self):
        new, changed = mirror.rewrite(ADA, mirror.card_keys(ADA_CARD, CARRY), owned(), None, self.STAMP)
        self.assertEqual(changed, [])
        self.assertEqual(new, ADA)

    def test_only_owned_lines_change(self):
        card = dict(ADA_CARD, tel=[{"label": "mobile", "value": "(555) 010-0199"}], bday="1990-01-02")
        new, changed = mirror.rewrite(ADA, mirror.card_keys(card, CARRY), owned(), None, self.STAMP)
        self.assertEqual(sorted(changed), ["BDAY", "TEL[CELL]"])
        old_lines, new_lines = ADA.split("\n"), new.split("\n")
        # Every line that is not an owned key and not `modified` is kept, byte for byte and in order.
        keep = lambda ls: [l for l in ls if not (owned().match(l.split(":")[0]) or l.startswith("modified:"))]
        self.assertEqual(keep(old_lines), keep(new_lines))
        self.assertIn("TEL[CELL]: \"(555) 010-0199\"", new_lines)
        self.assertIn("BDAY: \"1990-01-02\"", new_lines)
        self.assertIn(f"modified: {self.STAMP}", new_lines)
        self.assertEqual(new.split("\n---\n", 1)[1], ADA.split("\n---\n", 1)[1])  # the body, untouched

    def test_new_key_goes_among_owned_keys(self):
        new, _ = mirror.rewrite(ADA, mirror.card_keys(dict(ADA_CARD, org="Example Co"), CARRY), owned(), None, self.STAMP)
        fm = new.split("\n---\n", 1)[0].split("\n")
        self.assertLess(fm.index("ORG: Example Co"), fm.index("UID: urn:uuid:11111111-2222-3333-4444-555555555555"))

    def test_lost_field_is_removed(self):
        card = dict(ADA_CARD, email=[])
        new, changed = mirror.rewrite(ADA, mirror.card_keys(card, CARRY), owned(), None, self.STAMP)
        self.assertEqual(changed, ["EMAIL[HOME]"])
        self.assertNotIn("EMAIL[HOME]", new)

    def test_missing_card_sets_status_only(self):
        want = {k: v for k, v in mirror.current_values(mirror.blocks(mirror.split_note(ADA)[0])).items() if owned().match(k)}
        new, changed = mirror.rewrite(ADA, want, owned(), {"contact-status": "missing-from-contacts",
                                                           "contact-missing-since": "2026-10-01"}, self.STAMP)
        self.assertEqual(sorted(changed), ["contact-missing-since", "contact-status"])
        self.assertIn("contact-status: missing-from-contacts\n", new)
        self.assertIn('contact-missing-since: "2026-10-01"\n', new)
        self.assertIn("TEL[CELL]: (555) 010-0100", new)  # owned keys untouched on a missing card

    def test_card_back_removes_status(self):
        missing = ADA.replace("photos-faces: 3\n", "photos-faces: 3\ncontact-status: missing-from-contacts\ncontact-missing-since: 2026-09-01\n")
        new, changed = mirror.rewrite(missing, mirror.card_keys(ADA_CARD, CARRY), owned(), None, self.STAMP)
        self.assertEqual(sorted(changed), ["contact-missing-since", "contact-status"])
        self.assertNotIn("contact-", new)

    def test_quoting(self):
        for v in ("+1 555 0100", "00001", "1990-01-02", "true", "a: b", "#x", "O'Brien", "Ümlaut"):
            y = mirror.yaml_value(v)
            self.assertEqual(mirror.unquote(y), v, v)


# ---- the whole run, on a copy folder, with a stub reader

class Run(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="cm-test-"))
        self.dir = self.tmp / FOLDER
        self.dir.mkdir(parents=True)
        (self.dir / "27.20 Contacts.md").write_text("---\ntitle: Contacts\n---\n\n# Contacts\n")
        (self.dir / "Ada Example.md").write_text(ADA)
        (self.dir / "Bob Sample.md").write_text(ADA.replace("Ada", "Bob").replace("AAAA-0001", "BBBB-0002")
                                                .replace("11111111", "22222222"))
        (self.dir / "No Ids.md").write_text("---\ntitle: No Ids\n---\n\nbody\n")
        self.cfg = self.tmp / "config.json"
        self.cfg.write_text(json.dumps({"reader": ["false"], "folder": FOLDER, "keys": CARRY, "create": "none"}))

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def cards(self, cards):
        p = self.tmp / "cards.json"
        p.write_text(json.dumps({"cards": cards}))
        return ["cat", str(p)]

    def go(self, cards, *extra):
        out = subprocess.run([sys.executable, str(JOB / "mirror.py"), "--config", str(self.cfg), "--target-dir", str(self.tmp),
                              "--reader", *self.cards(cards), *extra], capture_output=True, text=True)
        return out.returncode, out.stdout + out.stderr

    def test_counts_and_writes(self):
        new_card = {"id": "CCCC-0003:ABPerson", "fn": "Cy Newcard"}
        rc, out = self.go([dict(ADA_CARD, org="Example Co"), new_card])
        self.assertEqual(rc, 0, out)
        self.assertIn("updated 1", out)
        self.assertIn("missing 1", out)      # Bob's card is gone
        self.assertIn("new 1", out)          # Cy has no note and none is created
        self.assertIn("unmatched 1", out)    # the note with no source and no UID
        self.assertIn("ORG: Example Co", (self.dir / "Ada Example.md").read_text())
        self.assertIn("contact-status: missing-from-contacts", (self.dir / "Bob Sample.md").read_text())
        self.assertFalse((self.dir / "Cy Newcard.md").exists())
        self.assertEqual((self.dir / "27.20 Contacts.md").read_text(), "---\ntitle: Contacts\n---\n\n# Contacts\n")

    def test_no_names_in_the_log(self):
        rc, out = self.go([dict(ADA_CARD, org="Example Co")])
        for word in ("Ada", "Bob", "Example", "555", "example.invalid"):
            self.assertNotIn(word, out)

    def test_plan_writes_nothing(self):
        before = {p.name: p.read_text() for p in self.dir.iterdir()}
        rc, out = self.go([dict(ADA_CARD, org="Example Co")], "--plan")
        self.assertEqual(rc, 0, out)
        self.assertEqual(before, {p.name: p.read_text() for p in self.dir.iterdir()})

    def test_second_run_is_quiet(self):
        self.go([ADA_CARD])
        first = (self.dir / "Bob Sample.md").read_text()
        rc, out = self.go([ADA_CARD])
        self.assertIn("updated 0", out)
        self.assertEqual(first, (self.dir / "Bob Sample.md").read_text())  # the missing-since date is kept

    def test_uid_fallback(self):
        (self.dir / "Ada Example.md").write_text(ADA.replace("source: addressbook://AAAA-0001:ABPerson\n", ""))
        card = dict(ADA_CARD, id="OTHER:ABPerson", uid="urn:uuid:11111111-2222-3333-4444-555555555555", org="Example Co")
        rc, out = self.go([card])
        self.assertIn("ORG: Example Co", (self.dir / "Ada Example.md").read_text())

    def test_bad_reader_output(self):
        p = self.tmp / "bad.json"
        p.write_text("not json")
        out = subprocess.run([sys.executable, str(JOB / "mirror.py"), "--config", str(self.cfg), "--target-dir", str(self.tmp),
                              "--reader", "cat", str(p)], capture_output=True, text=True)
        self.assertEqual(out.returncode, 3)

    def test_refuses_vault_target(self):
        env = dict(os.environ, CM_VAULT_ROOT=str(self.tmp))
        out = subprocess.run([sys.executable, str(JOB / "mirror.py"), "--config", str(self.cfg), "--target-dir", str(self.tmp),
                              "--reader", *self.cards([])], capture_output=True, text=True, env=env)
        self.assertEqual(out.returncode, 2)
        self.assertIn("inside the vault", out.stderr)

    def test_refuses_divorce_folder(self):
        self.cfg.write_text(json.dumps({"reader": ["false"], "folder": "80-89 Divorce/x", "keys": CARRY, "create": "none"}))
        rc, out = self.go([])
        self.assertEqual(rc, 2)


# ---- vault-mcp, through a fake bridge

FAKE_BRIDGE = r'''
import json, sys
state = json.load(open(sys.argv[1]))
def reply(i, result): print(json.dumps({"jsonrpc": "2.0", "id": i, "result": result}), flush=True)
def text(obj, err=False): return {"content": [{"type": "text", "text": obj if isinstance(obj, str) else json.dumps(obj)}], "isError": err}
for line in sys.stdin:
    m = json.loads(line)
    if "id" not in m: continue
    if m["method"] == "initialize": reply(m["id"], {"protocolVersion": "2025-06-18"}); continue
    name, a = m["params"]["name"], m["params"]["arguments"]
    if name == "obsidian_list_notes":
        reply(m["id"], text({"notes": [{"path": p} for p in sorted(state["notes"])], "has_more": False}))
    elif name == "obsidian_read_note":
        n = state["notes"][a["path"]]; reply(m["id"], text({"path": a["path"], "content": n["content"], "rev": n["rev"]}))
    elif name == "obsidian_write_note":
        n = state["notes"][a["path"]]
        state.setdefault("calls", []).append({k: a.get(k) for k in ("path", "overwrite", "if_rev") } | {"has_key": bool(a.get("idempotency_key"))})
        if a.get("if_rev") != n["rev"] or state.get("conflict"): reply(m["id"], text("Error [rev_conflict]", True))
        else: n["content"] = a["content"]; n["rev"] += 1; reply(m["id"], text({"ok": True}))
        json.dump(state, open(sys.argv[1], "w"))
'''


class Mcp(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="cm-mcp-"))
        self.state = self.tmp / "state.json"
        self.bridge = self.tmp / "bridge.py"
        self.bridge.write_text(FAKE_BRIDGE)
        self.state.write_text(json.dumps({"notes": {f"{FOLDER}/Ada Example.md": {"content": ADA, "rev": 7}}}))
        self.cfg = self.tmp / "config.json"
        self.cfg.write_text(json.dumps({"reader": ["false"], "folder": FOLDER, "keys": CARRY, "create": "none",
                                        "bridge": [sys.executable, str(self.bridge), str(self.state)]}))
        (self.tmp / "cards.json").write_text(json.dumps({"cards": [dict(ADA_CARD, org="Example Co")]}))

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def go(self):
        out = subprocess.run([sys.executable, str(JOB / "mirror.py"), "--config", str(self.cfg), "--reader", "cat",
                              str(self.tmp / "cards.json")], capture_output=True, text=True)
        return out.returncode, out.stdout + out.stderr, json.loads(self.state.read_text())

    def test_write_uses_if_rev_and_key(self):
        rc, out, st = self.go()
        self.assertEqual(rc, 0, out)
        self.assertEqual(st["calls"], [{"path": f"{FOLDER}/Ada Example.md", "overwrite": True, "if_rev": 7, "has_key": True}])
        self.assertIn("ORG: Example Co", st["notes"][f"{FOLDER}/Ada Example.md"]["content"])

    def test_conflict_is_skipped_not_forced(self):
        st = json.loads(self.state.read_text()); st["conflict"] = True; self.state.write_text(json.dumps(st))
        rc, out, st = self.go()
        self.assertEqual(rc, 0, out)
        self.assertIn("conflict 1", out)
        self.assertEqual(st["notes"][f"{FOLDER}/Ada Example.md"]["content"], ADA)

    def test_no_bridge_is_a_skip(self):
        self.cfg.write_text(json.dumps({"reader": ["false"], "folder": FOLDER, "keys": CARRY, "create": "none",
                                        "bridge": [str(self.tmp / "no-such-bridge")]}))
        rc, out, _ = self.go()
        self.assertEqual(rc, 0, out)
        self.assertIn("SKIPPED", out)


# ---- run.sh gates

class Gates(unittest.TestCase):
    def run_sh(self, **env):
        pause = Path(tempfile.mkdtemp(prefix="cm-gate-")) / "Pause.md"
        pause.write_text("---\npaused: false\n---\n")
        e = {"HOME": os.environ["HOME"], "PATH": "/usr/bin:/bin", "PAUSE_NOTE": str(pause), "CM_LOAD5": "1.0", "CM_SESSIONS": "3"}
        e.update(env)
        out = subprocess.run(["/bin/bash", str(JOB / "run.sh"), "--target-dir", "/nonexistent-cm", "--reader", "true"],
                             capture_output=True, text=True, env=e)
        shutil.rmtree(pause.parent)
        return out.returncode, out.stdout + out.stderr

    def test_load_gate(self):
        rc, out = self.run_sh(CM_LOAD5="8.0")
        self.assertEqual(rc, 0); self.assertIn("load", out); self.assertIn("SKIPPED", out)

    def test_session_gate(self):
        rc, out = self.run_sh(CM_SESSIONS="20")
        self.assertEqual(rc, 0); self.assertIn("20 live sessions", out)

    def test_open_gates_reach_the_job(self):
        rc, out = self.run_sh()
        self.assertIn("gates: pause clear", out)
        self.assertEqual(rc, 3)  # the reader `true` prints no JSON: the job itself ran and failed loudly


if __name__ == "__main__":
    unittest.main()
