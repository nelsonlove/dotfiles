#!/usr/bin/env python3
"""[test artifact — safe to delete] generate the inversion's battery as payload FILES plus a manifest.

Written in python on purpose: two hand-quoted shell batteries in this package produced false results —
a `\\b` inside a python -c string became a backspace, and `\\u0027` escapes lost their spaces before jq
saw them. Payload bytes must not pass through a shell.
"""
import json, pathlib

OUT = pathlib.Path("/tmp/v3/cases")
OUT.mkdir(parents=True, exist_ok=True)
for old in OUT.glob("*.json"):
    old.unlink()
Q = "qan:00-09 System/00 System management/00.14 QuickAdd choices"
cases = []


def c(want, label, payload):
    cases.append((want, label, payload))


def bash(cmd, **extra):
    ti = {"command": cmd}
    ti.update(extra)
    return {"tool_name": "Bash", "tool_input": ti}


# --- fail closed -------------------------------------------------------------------------------------
c(2, "tool_input is a STRING (this used to be ALLOWED)", {"tool_name": "Bash", "tool_input": 'obsidian quickadd choice="x"'})
c(2, "tool_input is an ARRAY", {"tool_name": "Bash", "tool_input": ["obsidian quickadd choice=x"]})
c(2, "tool_input is a NUMBER", {"tool_name": "Bash", "tool_input": 42})
c(2, "no tool name", {"tool_input": {"command": "ls"}})
c(2, "an empty tool name", {"tool_name": "", "tool_input": {"command": "ls"}})
c(0, "tool_input absent entirely", {"tool_name": "Bash"})
c(0, "tool_input null", {"tool_name": "Bash", "tool_input": None})

# --- the four roads: refuse whatever they name -------------------------------------------------------
c(2, "a run tool, an accept verb id", {"tool_name": "mcp__vault-mcp__obsidian_run_command", "tool_input": {"command_id": f"{Q}/Verify current note.md#choice"}})
c(2, "a run tool, an ORDINARY command id", {"tool_name": "mcp__vault-mcp__obsidian_run_command", "tool_input": {"command_id": "editor:toggle-bold"}})
c(2, "a vault tool whose name says execute", {"tool_name": "mcp__vault-mcp__obsidian_execute_choice", "tool_input": {"choice": "New task"}})
c(2, "CLI command id=, an accept verb", bash('obsidian vault=obsidian command id="quickadd:choice:Verify current note"'))
c(2, "CLI command id=, an ordinary command", bash('obsidian command id="editor:toggle-bold"'))
c(2, "CLI quickadd choice=", bash('obsidian vault=obsidian quickadd choice="New task"'))
c(2, "CLI quickadd:run", bash('obsidian quickadd:run choice="x"'))
c(2, "CLI quickadd:run-template-from-folder", bash("obsidian quickadd:run-template-from-folder folder=x"))
c(2, "eval invoking a command by id", bash('obsidian eval code="app.commands.executeCommandById(\\"editor:toggle-bold\\")"'))
c(2, "eval invoking a choice", bash('obsidian eval code="app.plugins.plugins.quickadd.api.executeChoice(\\"x\\")"'))
c(2, "an advanced-uri opened", bash("open -g 'obsidian://advanced-uri?vault=obsidian&commandid=quickadd%3Achoice%3Ax'"))
c(2, "an advanced-uri, DOUBLE encoded", bash("open -g 'obsidian://advanced-uri?vault=obsidian&commandid=quickadd%253Achoice%253Ax'"))
c(2, "an advanced-uri through python webbrowser", bash("python3 -c \"import webbrowser; webbrowser.open('obsidian://advanced-uri?commandid=x')\""))
c(2, "the JXA open location form", bash("osascript -l JavaScript -e 'Application(\"Obsidian\").openLocation(\"obsidian://advanced-uri?commandid=x\")'"))
c(2, "the Local REST API on loopback", bash("curl -s -X POST http://127.0.0.1:27123/commands/ -d x"))
c(2, "a call wrapped in bash -c", bash('bash -c "obsidian command id=x"'))
c(2, "a call over ssh to another ship", bash("ssh orange 'obsidian quickadd choice=x'"))
c(2, "a call after a stderr redirect", bash("command -v jq 2>/dev/null; obsidian quickadd choice=x"))
c(2, "a call after a herestring", bash("cat <<< hello ; obsidian command id=x"))
c(2, "a call AFTER a heredoc write (was #59)", bash("cat <<EOF >> /tmp/n.md\nprose about the road\nEOF\nobsidian command id=x"))
c(2, "a call after a # comment holding <<", bash("# the wall was << and nothing else\nobsidian command id=x"))
c(2, "a call inside a line whose comment comes first", bash("echo hi # obsidian command id=y\nobsidian command id=x"))

# --- prose, reads, writes: the direction that reverted version one -----------------------------------
c(0, "R1 a python heredoc writing about eval and executeChoice", bash('python3 - <<PY\nopen("/tmp/nb.md","a").write("the guard watches for eval and executeChoice(...)")\nPY'))
c(0, "R2 a heredoc adding the rule-19 sentence to a note", bash("cat <<EOF >> ~/obsidian/01.65.md\nNo rank invokes an accept verb (Verify current note, Reopen current note, Request revision, Answer current note) through the palette API, a command call or an eval.\nEOF"))
c(0, "R3 a heredoc naming the four verbs in a notebook section", bash("cat <<EOF >> ~/obsidian/nb.md\n## The quickadd verbs\nVerify current note, Reopen current note, Request revision and Answer current note are Nelson-only.\nEOF"))
c(0, "R4 writing a harness that stubs executeChoice", bash("cat > /tmp/h.js <<JS\nconst quickAddApi = { executeChoice: (n) => calls.push(n) };\nJS"))
c(0, "R4b running that harness with node", bash("node /tmp/h.js"))
c(0, "a heredoc QUOTING a whole CLI call", bash('cat <<EOF >> /tmp/doc.md\nto run one by hand: obsidian vault=obsidian command id="quickadd:choice:x"\nEOF'))
c(0, "a heredoc with a QUOTED delimiter", bash("cat <<'EOF' >> /tmp/doc.md\nobsidian quickadd choice=x\nEOF"))
c(0, "the <<- dash form", bash("cat <<-EOF >> /tmp/doc.md\n\tobsidian command id=x\n\tEOF"))
c(0, "two heredocs, the call inside the second", bash("cat <<A > /tmp/a; cat <<B > /tmp/b\nfirst\nA\nobsidian command id=x\nB"))
c(0, "the delimiter word appearing inside the body", bash("cat <<EOF >> /tmp/d.md\nthe word EOF is in this line but not alone\nobsidian command id=x\nEOF"))
c(0, "printf then a trailing redirect", bash("printf '%s' 'obsidian command id=x' > /tmp/doc.md"))
c(0, "echo piped to tee", bash("echo 'obsidian quickadd choice=x' | tee -a /tmp/doc.md"))
c(0, "the uri WRITTEN rather than opened", bash("printf '%s' 'obsidian://advanced-uri?commandid=x' > /tmp/doc.md"))
c(0, "the uri inside a markdown link", bash("printf '%s' 'see [it](obsidian://advanced-uri?commandid=x)' >> /tmp/n.md"))
c(0, "the uri piped to pbcopy", bash("echo 'obsidian://advanced-uri?commandid=x' | pbcopy"))
c(0, "a commit message quoting a call", bash("git commit -m 'document obsidian command id=x and the eval form'"))
c(0, "a comment mentioning a call", bash("# obsidian command id=x is the road\necho done"))
c(0, "a grep for the verb names", bash("grep -rn 'Verify current note' claude/ | head"))
c(0, "a grep for the invocation forms", bash("grep -rn 'commandid=quickadd' claude/ tickle/"))
c(0, "the CLI append verb, content naming verbs", bash('obsidian vault=obsidian append file=x content="Verify current note is Nelson-only"'))
c(0, "the CLI rename verb", bash("obsidian vault=obsidian rename path=a.md name=b"))
c(0, "the CLI vault info read", bash("obsidian vault=obsidian vault info=path"))
c(0, "an eval that reads and invokes nothing", bash('obsidian eval code="app.workspace.getActiveFile().path"'))
c(0, "a note NAMED like a verb, opened", bash('obsidian open file="00-09 System/Verify current note.md"'))
c(0, "the REST API on an EXTERNAL host", bash("curl -s https://example.com/commands/ -d x"))
c(0, "a vault-mcp WRITE tool discussing verbs", {"tool_name": "mcp__vault-mcp__obsidian_append_note", "tool_input": {"path": "01.41.md", "content": "Verify current note and Request revision are Nelson-only."}})
c(0, "a vault-mcp READ tool", {"tool_name": "mcp__vault-mcp__obsidian_read_note", "tool_input": {"path": "01.65.md"}})
c(0, "another server tool named execute", {"tool_name": "mcp__claude-in-chrome__shortcuts_execute", "tool_input": {"name": "Verify current note"}})
c(0, "a Bash description naming a call", bash("ls -la", description="before the obsidian command id=x work"))
c(0, "an ordinary path mentioning obsidian", bash('ls -la "$HOME/obsidian/00-09 System" | head'))
c(0, "a large vault heredoc write", bash("cat <<EOF >> ~/obsidian/x.md\n" + ("the note lives at ~/obsidian/00-09 System/x.md\n" * 200) + "EOF"))

manifest = []
for i, (want, label, payload) in enumerate(cases, 1):
    name = f"c{i:03d}.json"
    (OUT / name).write_text(json.dumps(payload))
    manifest.append({"file": name, "want": want, "label": label})
# the two malformed-text cases cannot be JSON, so they are written raw
(OUT / "x001.raw").write_text("nope")
(OUT / "x002.raw").write_text("")
(OUT / "x003.raw").write_text("[1,2,3]")
manifest += [
    {"file": "x001.raw", "want": 2, "label": "not JSON"},
    {"file": "x002.raw", "want": 2, "label": "empty input"},
    {"file": "x003.raw", "want": 2, "label": "a JSON array as the whole payload"},
]
(OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))
print(len(manifest), "cases written to", OUT)
