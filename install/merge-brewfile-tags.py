#!/usr/bin/env python3
"""Re-apply `# group:NAME` tags after `brew bundle dump` regenerates the Brewfile.

`brew bundle dump --force` rewrites the whole file, dropping both the group
tags and any non-bundle lines (cargo/uv/npm). This restores them:

  merge-brewfile-tags.py OLD_TAGGED_BREWFILE NEW_DUMPED_BREWFILE

- Each brew/cask/mas entry in NEW gets its group from OLD (matched by name).
- Entries with no known tag get `# group:_untagged` and are reported on stderr
  so you can categorize them.
- Non-bundle lines (cargo/uv/npm) + their preceding comment are carried over.
NEW is rewritten in place.
"""
import re
import sys

OLD, NEW = sys.argv[1], sys.argv[2]
ENTRY = re.compile(r'^(brew|cask|mas)\s+"([^"]+)"')
NONBUNDLE = re.compile(r'^(cargo|uv|npm|pnpm|gem)\s')


def parse_old(path):
    tags, extras = {}, []
    prev = None
    for raw in open(path):
        line = raw.rstrip("\n")
        m = ENTRY.match(line)
        if m:
            c = re.search(r"#\s*group:.*$", line)  # whole trailing annotation
            if c:
                tags[(m.group(1), m.group(2))] = c.group(0)
        elif NONBUNDLE.match(line):
            if prev and prev.lstrip().startswith("#"):
                extras.append(prev)
            extras.append(line)
        prev = line
    return tags, extras


def main():
    tags, extras = parse_old(OLD)
    out, untagged = [], []
    for raw in open(NEW):
        line = raw.rstrip("\n")
        line = re.sub(r"\s*#\s*group:.*$", "", line)  # idempotent
        m = ENTRY.match(line)
        if m:
            key = (m.group(1), m.group(2))
            ann = tags.get(key)
            if ann is None:
                ann = "# group:_untagged"
                untagged.append(f"{m.group(1)} {m.group(2)}")
            out.append(f"{line}  {ann}")
        else:
            out.append(line)
    if extras:
        out.append("")
        out.append("# --- non-Homebrew packages (carried over; managed separately) ---")
        out.extend(extras)
    with open(NEW, "w") as f:
        f.write("\n".join(out) + "\n")
    if untagged:
        sys.stderr.write(
            f"  ! {len(untagged)} new untagged entries (set a # group: for each):\n"
            + "".join(f"      {u}\n" for u in untagged)
        )


main()
