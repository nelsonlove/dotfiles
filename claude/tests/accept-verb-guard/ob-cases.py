#!/usr/bin/env python3
"""[test artifact — safe to delete] the obsidian ship's cases, asked through the captain.

Nothing is executed: each case is the hook's own answer to a payload on stdin.
"""
import json, subprocess, sys

G = sys.argv[1] if len(sys.argv) > 1 else "/Users/nelson/repos/system/dotfiles/.claude/worktrees/feat+accept-verb-guard-v2/claude/hooks/accept-verb-guard.sh"
fails = 0
n = 0


def t(want, label, payload):
    global fails, n
    n += 1
    r = subprocess.run([G], input=json.dumps(payload).encode(), capture_output=True)
    ok = r.returncode == want
    if not ok:
        fails += 1
    first = (r.stderr.decode(errors="replace").splitlines() or [""])[0]
    print(f'{"PASS" if ok else "FAIL"}  {label:<62} rc={r.returncode}'
          + ("" if ok else f' (owes {want})  {first[:120]}'))


print("=== (1) the OB ship's vault-mcp tools must PASS — their names are not run-tool names")
t(0, "obsidian_plugin_toggle", {"tool_name": "mcp__vault-mcp__obsidian_plugin_toggle", "tool_input": {"plugin": "obsidian-linter", "enabled": True}})
t(0, "obsidian_plugin_reload", {"tool_name": "mcp__vault-mcp__obsidian_plugin_reload", "tool_input": {"plugin": "fileclass"}})
t(0, "obsidian_force_reindex", {"tool_name": "mcp__vault-mcp__obsidian_force_reindex", "tool_input": {}})
t(0, "obsidian_check_links", {"tool_name": "mcp__vault-mcp__obsidian_check_links", "tool_input": {"path": "00-09 System/01 System architecture"}})
t(0, "obsidian_move_note", {"tool_name": "mcp__vault-mcp__obsidian_move_note", "tool_input": {"from": "a.md", "to": "b.md"}})
t(0, "obsidian_get_command_ids (name says command)", {"tool_name": "mcp__vault-mcp__obsidian_get_command_ids", "tool_input": {"filter": "quickadd"}})

print("\n=== (2) the run tool must REFUSE")
t(2, "obsidian_run_command", {"tool_name": "mcp__vault-mcp__obsidian_run_command", "tool_input": {"command_id": "editor:toggle-bold"}})

print("\n=== (3) THE ONE THAT MATTERS: a note BODY documenting a call, handed to a writer, must PASS")
body = (
    "# The roads this guard refuses\n\n"
    "The obsidian CLI form is:\n\n"
    "    obsidian vault=obsidian command id=\"quickadd:choice:Verify current note\"\n\n"
    "and the advanced-uri form is obsidian://advanced-uri?vault=obsidian&commandid=quickadd%3Achoice%3AVerify%20current%20note\n\n"
    "Both are Nelson's to run, never a session's.\n"
)
t(0, "obsidian_write_note whose body documents both roads", {"tool_name": "mcp__vault-mcp__obsidian_write_note", "tool_input": {"path": "01.41 notes.md", "content": body}})
t(0, "obsidian_append_note whose body documents both roads", {"tool_name": "mcp__vault-mcp__obsidian_append_note", "tool_input": {"path": "01.41 notes.md", "content": body}})
t(0, "obsidian_write_note, the CLI line alone", {"tool_name": "mcp__vault-mcp__obsidian_write_note", "tool_input": {"path": "x.md", "content": "obsidian vault=obsidian command id=x"}})

print("\n=== (4) the CLI's non-invoking verbs must PASS")
t(0, "CLI append", {"tool_name": "Bash", "tool_input": {"command": 'obsidian vault=obsidian append file="x" content="a note"'}})
t(0, "CLI open with a bare file argument", {"tool_name": "Bash", "tool_input": {"command": 'obsidian vault=obsidian open file="00-09 System/x.md"'}})
t(0, "CLI with a bare path and no command word", {"tool_name": "Bash", "tool_input": {"command": "obsidian /Users/nelson/obsidian/x.md"}})

print(f"\n{n} cases, {fails} failed")
sys.exit(1 if fails else 0)
