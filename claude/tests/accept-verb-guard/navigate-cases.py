#!/usr/bin/env python3
"""[test artifact — safe to delete] the browser road: the guard is registered on
`mcp__claude-in-chrome__navigate` by EXACT tool name, not on the claude-in-chrome family, because a hook on
every browser call is latency for nothing.

The condition these cases exist for: the refusal keys on `commandid` and NOTHING else. Opening a NOTE is not
invoking a command, and the fleet opens notes in the browser, so every other obsidian:// form must pass —
otherwise this entry would ship a browser that cannot open a note.

Nothing is executed and no URL is opened: each case is the hook's own answer to a payload on stdin.
"""
import json, subprocess, sys

G = sys.argv[1] if len(sys.argv) > 1 else "/Users/nelson/repos/system/dotfiles/.claude/worktrees/feat+accept-verb-guard-v2/claude/hooks/accept-verb-guard.sh"
n = 0
fails = 0


def t(want, label, tool_input, tool="mcp__claude-in-chrome__navigate"):
    global n, fails
    n += 1
    r = subprocess.run([G], input=json.dumps({"tool_name": tool, "tool_input": tool_input}).encode(),
                       capture_output=True)
    ok = r.returncode == want
    if not ok:
        fails += 1
    first = (r.stderr.decode(errors="replace").splitlines() or [""])[0]
    print(f'{"PASS" if ok else "FAIL"}  {label:<58} rc={r.returncode}' + ("" if ok else f' (owes {want})  {first[:100]}'))


print("=== (1) ordinary browsing must pass")
t(0, "an ordinary https page", {"url": "https://example.com/docs"})
t(0, "the Obsidian help site", {"url": "https://help.obsidian.md/Advanced+topics/Using+obsidian+URI"})
t(0, "a github PR page", {"url": "https://github.com/nelsonlove/dotfiles/pull/58"})
t(0, "a page whose URL contains the word commandid", {"url": "https://example.com/docs?about=commandid"})

print("\n=== (2) obsidian:// forms that OPEN rather than invoke must pass")
t(0, "obsidian://open with a file", {"url": "obsidian://open?vault=obsidian&file=00-09%20System%2Fx.md"})
t(0, "obsidian://open with a path", {"url": "obsidian://open?vault=obsidian&path=x.md"})
t(0, "advanced-uri with filepath=", {"url": "obsidian://advanced-uri?vault=obsidian&filepath=00-09%20System%2Fx.md"})
t(0, "advanced-uri with uid=", {"url": "obsidian://advanced-uri?vault=obsidian&uid=9f2c1a"})
t(0, "advanced-uri with a heading", {"url": "obsidian://advanced-uri?vault=obsidian&filepath=x.md&heading=Decisions"})
t(0, "advanced-uri with a block ref", {"url": "obsidian://advanced-uri?vault=obsidian&filepath=x.md&block=abc123"})
t(0, "advanced-uri writing content to a note", {"url": "obsidian://advanced-uri?vault=obsidian&filepath=x.md&mode=append&data=a%20line"})
t(0, "obsidian://search", {"url": "obsidian://search?vault=obsidian&query=quickadd"})

print("\n=== REGRESSION: why the check is SCHEME POSITION and not substring")
# Both of these load an https page and invoke nothing. They were REFUSED when the check asked whether the
# string CONTAINED an obsidian:// uri carrying a commandid, and the first is what a session does when it
# reads Obsidian own URI documentation. Position, not presence — the same principle as command position on
# the Bash road.
t(0, "the documentation page with the uri as its anchor", {"url": "https://help.obsidian.md/uri#obsidian://advanced-uri?commandid=x"})
t(0, "an https page carrying the uri as a parameter", {"url": "https://example.com/redirect?to=obsidian://advanced-uri%3Fcommandid%3Dx"})

print("\n=== (3) the invoking form must refuse")
t(2, "advanced-uri with commandid", {"url": "obsidian://advanced-uri?vault=obsidian&commandid=quickadd%3Achoice%3Ax"})
t(2, "advanced-uri with commandid, double encoded", {"url": "obsidian://advanced-uri?vault=obsidian&commandid=quickadd%253Achoice%253Ax"})
t(2, "commandid first in the query", {"url": "obsidian://advanced-uri?commandid=editor%3Atoggle-bold&vault=obsidian"})
t(2, "commandid in a second URL field", {"url": "https://example.com", "target": "obsidian://advanced-uri?commandid=x"})

print("\n=== the entry is by EXACT name, so a sibling browser tool is not judged")
t(0, "a different claude-in-chrome tool with the same URL",
  {"url": "obsidian://advanced-uri?commandid=x"}, tool="mcp__claude-in-chrome__read_page")
print(f"\n{n} cases, {fails} failed")
sys.exit(1 if fails else 0)
