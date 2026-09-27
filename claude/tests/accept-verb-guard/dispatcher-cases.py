#!/usr/bin/env python3
"""[test artifact — safe to delete] the dispatcher read ONE level, and the URI road's second spelling.

`obsidian_call_tool` names another tool and carries its arguments, so its payload IS a call. It is not
refused wholesale — that would refuse all 65 tools it routes to the day code mode is on — so the same rule
is applied one level down. One level only: a dispatcher naming a dispatcher is refused rather than
followed, because a target the guard cannot read must not run.

Nothing is executed: each case is the hook's own answer to a payload on stdin.
"""
import json, subprocess, sys

G = sys.argv[1] if len(sys.argv) > 1 else "/Users/nelson/repos/system/dotfiles/.claude/worktrees/feat+accept-verb-guard-v2/claude/hooks/accept-verb-guard.sh"
n = 0
fails = 0


def t(want, label, tool_input, tool="mcp__vault-mcp__obsidian_call_tool"):
    global n, fails
    n += 1
    r = subprocess.run([G], input=json.dumps({"tool_name": tool, "tool_input": tool_input}).encode(),
                       capture_output=True)
    ok = r.returncode == want
    if not ok:
        fails += 1
    first = (r.stderr.decode(errors="replace").splitlines() or [""])[0]
    print(f'{"PASS" if ok else "FAIL"}  {label:<60} rc={r.returncode}' + ("" if ok else f' (owes {want})  {first[:100]}'))


print("=== the dispatcher, one level down")
t(2, "dispatching the run tool", {"name": "obsidian_run_command", "args": {"command_id": "quickadd:run"}})
t(2, "dispatching obsidian_cli with a command word", {"name": "obsidian_cli", "args": {"command": "command", "params": {"id": "x"}}})
t(2, "dispatching obsidian_cli with quickadd", {"name": "obsidian_cli", "args": {"command": "quickadd", "params": {"choice": "x"}}})
t(2, "dispatching obsidian_cli eval that CALLS", {"name": "obsidian_cli", "args": {"command": "eval", "params": {"code": "app.commands.executeCommandById('x')"}}})
t(2, "dispatching itself", {"name": "obsidian_call_tool", "args": {"name": "obsidian_run_command"}})
t(2, "naming no tool at all", {"args": {"command_id": "x"}})
t(2, "an empty tool name", {"name": "", "args": {}})
t(0, "dispatching a read tool", {"name": "obsidian_read_note", "args": {"path": "x.md"}})
t(0, "dispatching a write tool whose body documents a call", {"name": "obsidian_write_note", "args": {"path": "x.md", "content": "run obsidian command id=x by hand"}})
t(0, "dispatching obsidian_cli with append", {"name": "obsidian_cli", "args": {"command": "append", "params": {"file": "x", "content": "a note"}}})
t(0, "dispatching obsidian_cli eval that only MENTIONS the api", {"name": "obsidian_cli", "args": {"command": "eval", "params": {"code": "// never call executeChoice"}}})

print("\n=== the eval body under a key that is not `code`")
t(2, "obsidian_cli eval with the body under params.js", {"command": "eval", "params": {"js": "app.commands.executeCommandById('x')"}},
  tool="mcp__vault-mcp__obsidian_cli")
t(0, "obsidian_cli append whose content documents a call", {"command": "append", "params": {"file": "x", "content": "obsidian command id=x"}},
  tool="mcp__vault-mcp__obsidian_cli")
t(2, "obsidian_cli with a padded command word", {"command": " command ", "params": {"id": "x"}},
  tool="mcp__vault-mcp__obsidian_cli")

print("\n=== the URI road's second spelling")
t(2, "navigate with commandname=", {"url": "obsidian://advanced-uri?vault=obsidian&commandname=Verify%20current%20note"},
  tool="mcp__claude-in-chrome__navigate")
t(0, "navigate to a note by filepath", {"url": "obsidian://advanced-uri?vault=obsidian&filepath=x.md"},
  tool="mcp__claude-in-chrome__navigate")
print(f"\n{n} cases, {fails} failed")
sys.exit(1 if fails else 0)
