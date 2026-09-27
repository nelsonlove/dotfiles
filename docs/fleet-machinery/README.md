# Fleet machinery — surveys that precede the code

Two documents, both produced by a throwaway soak session during PR #58 and landed here before any of package 4's code, so that the reasoning exists outside `/tmp` and outside anyone's memory.

Neither is doctrine and neither is a record. They are **measurements of this repo as it stood on 2026-09-27**, with their own corrections left visible beside their claims, because the corrections are the most useful part.

| file | what it measured | what it is for |
|---|---|---|
| `Duplicated fleet machinery survey.md` | every named function and constant appearing in more than one of the nine scripts under `claude/bin/` and `claude/hooks/`, with line numbers and whether the bodies are byte-identical | the input to `claude/bin/_fleet-ranks.sh`: it says which nine names belong in a shared file, which single-definition constants must travel with them or drift, and which same-named functions must NOT be shared |
| `Pause-flag parser duplication.md` | the 69-line pause-flag parser duplicated between `claude/hooks/pause-guard.sh` and `tickle/scripts/_lib/pause-gate.sh`, its parameter contract, and five ways the two can drift, ranked by cost | the input to the pause-flag half of package 4, which unifies the two copies only if one sourced file can be PROVEN to resolve from both install roads |

## What to read them for, if you are reading one of them for the first time

**The traps, not the tables.** The survey's value is not the list of nine names; it is the four warnings around it. `on_exit` is defined four times with four genuinely different jobs, so extracting by name would break all four. `die` is defined three times with a different program name baked into each, so sharing it needs a `PROG` variable and is a behaviour change in the error text if anyone gets it wrong. `FLOATING_SHIP` is a single definition that sits under `KNOWN_SHIPS` and must move with it or the two will drift. And `rank_of_name` differs between its two copies **in the comment only** — the `case` arms are byte-identical — which is the shape a hand-maintained duplicate takes just before it stops being identical at all.

**Both documents correct themselves in public.** The survey's author first claimed that the accept-verb battery would stay green if only one of two hardcoded lists were renamed, tested it rather than leaving it asserted, and found the opposite (10 of 39 cases fail on one list, 2 of 39 on the other). The pause-flag document's first version asked whether the two install roads agree on a repo root, got two different answers, and printed NOT PROVEN — a wrong verdict from a wrong question, since the hook sits two levels below the root and the gate three. Both corrections are left beside the original claims on purpose. A document that shows only the conclusions that held is worth less than one that shows which were checked.
