#!/usr/bin/env python3
"""[test artifact — safe to delete] the `obsidian_cli` exception, both ways.

THE LIMIT, stated because it bears on every line below: `obsidian_cli` is not exposed to this fleet's
sessions, so every case here is a synthetic stdin payload and the guard has never seen a live call of it.
Nothing is executed: each case is the hook's own answer to a payload on stdin.
"""
import json, subprocess, sys

G = sys.argv[1] if len(sys.argv) > 1 else "/Users/nelson/repos/system/dotfiles/.claude/worktrees/feat+accept-verb-guard-v2/claude/hooks/accept-verb-guard.sh"
n = 0
fails = 0


def t(want, label, tool_input, tool="mcp__vault-mcp__obsidian_cli"):
    global n, fails
    n += 1
    r = subprocess.run([G], input=json.dumps({"tool_name": tool, "tool_input": tool_input}).encode(), capture_output=True)
    ok = r.returncode == want
    if not ok:
        fails += 1
    first = (r.stderr.decode(errors="replace").splitlines() or [""])[0]
    print(f'{"PASS" if ok else "FAIL"}  {label:<62} rc={r.returncode}' + ("" if ok else f' (owes {want})  {first[:110]}'))


DOC = ("The CLI form is `obsidian vault=obsidian command id=\"quickadd:choice:Verify current note\"` and "
       "the uri form is obsidian://advanced-uri?vault=obsidian&commandid=quickadd%3Achoice%3AVerify%20current%20note. "
       "Both are Nelson's to run.")

print("=== the command word IS the road: these must REFUSE")
t(2, "command=command with an id", {"command": "command", "params": {"id": "quickadd:choice:x"}})
t(2, "command=quickadd with a choice", {"command": "quickadd", "params": {"choice": "New task"}})
t(2, "command=quickadd:run", {"command": "quickadd:run", "params": {"choice": "x"}})
t(2, "command=quickadd:run-template-from-folder", {"command": "quickadd:run-template-from-folder", "params": {"folder": "x"}})
t(2, "command=eval whose code invokes a choice", {"command": "eval", "params": {"code": "app.plugins.plugins.quickadd.api.executeChoice('x')"}})
t(2, "command=eval whose code invokes a command id", {"command": "eval", "params": {"code": "app.commands.executeCommandById('editor:toggle-bold')"}})
t(2, "the command word in another casing", {"command": "QuickAdd", "params": {"choice": "x"}})

print("\n=== the long tail must PASS")
t(0, "command=append", {"command": "append", "params": {"file": "x", "content": "a note"}})
t(0, "command=help", {"command": "help"})
t(0, "command=theme:set", {"command": "theme:set", "params": {"name": "Minimal"}})
t(0, "command=history:list", {"command": "history:list", "params": {"file": "x.md"}})
t(0, "command=eval that reads and invokes nothing", {"command": "eval", "params": {"code": "app.workspace.getActiveFile().path"}})

print("\n=== CONDITION 1: only the command line is read, never the content")
t(0, "command=append whose CONTENT documents both roads", {"command": "append", "params": {"file": "x.md", "content": DOC}})
t(0, "command=create whose CONTENT documents both roads", {"command": "create", "params": {"path": "x.md", "content": DOC}})
# KNOWN, REPORTED, NOT FIXED: the eval road tests for the API name as a SUBSTRING, so code that merely
# MENTIONS it in a string is refused. It is the same substring-in-free-text failure the inversion exists
# to kill, surviving inside one road, and it predates this commit — the Bash eval road does it too. The
# case is pinned at what the guard actually does so this file never lies; the proposal upstairs is to
# require a call shape (the name followed by `(`) rather than the bare name.
t(2, "KNOWN FALSE REFUSAL: eval code that only MENTIONS executeChoice", {"command": "eval", "params": {"code": "app.vault.create('n.md', 'the api is executeChoice, do not call it')"}})

print("\n=== the exception is by EXACT name, so these are judged by name alone")
t(0, "a write tool whose body documents both roads", {"path": "x.md", "content": DOC}, tool="mcp__vault-mcp__obsidian_write_note")
t(0, "a tool whose name merely contains cli", {"command": "quickadd", "params": {"choice": "x"}}, tool="mcp__vault-mcp__obsidian_cli_history")
t(2, "the run tool, still refused by name", {"command_id": "editor:toggle-bold"}, tool="mcp__vault-mcp__obsidian_run_command")

print(f"\n{n} cases, {fails} failed")
sys.exit(1 if fails else 0)
