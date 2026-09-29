#!/usr/bin/env bash
# notebook-roots.sh — the two notebook roots, and the entries under them.
#
# WHY THERE ARE TWO. Ruled 2026-09-29: an ENDED notebook entry moves out of `03.04 Records/Agent notebook/`
# into `03 Agents/03.09 Archive/Agent notebook/`, while a RUNNING entry stays. So the newest entry for a
# session can sit in either root, and anything that looks one up must read both.
#
# EXACTLY TWO ROOTS, AND ONE FOLDER DOWN. Nelson narrowed this himself — "narrow it" — after the first version
# swept every `03.09*` directory: the roots are `<agents>/03.04 Records/Agent notebook` and
# `<agents>/03.09 Archive/Agent notebook`, and the entries are `<root>/YYYY-MM/Agent session *.md`, one month
# folder down and no deeper. Measured against the live tree before the narrowing landed: all 489 entries sit
# at exactly that depth and the archive holds none, so the narrow rule reads the same population the glob did
# — without ever walking a folder nobody meant it to.
#
# WHY IT IS A LIBRARY. Four callers need the same answer: `wake-session.sh` (the reporting-line index and the
# post-rm path), `claude/bin/sweep-jobs.sh`, the roster reader, and `claude/tests/fleet-ranks/status-dual-read.sh`
# (its real-population section, since 2026-09-29). A shell function cannot be reached from
# another script, so the alternative was three copies of one rule — the shape that drifted in the pause parser
# before #61 and again between the library and the awk in #68. One definition, three callers, and
# `claude/tests/fleet-ranks/wake-two-roots.sh` passing unchanged is the proof the move changed nothing.
#
# IT READS NO GLOBAL OF ITS CALLER'S. Every input is an argument, including the DERIVATION of the defaults:
# a library that reached for `$AGENTS_DIR` would be a second place where the default lives, which is the thing
# this file exists to prevent.
#
# THE SEAMS, which behave exactly as #69 has them and must keep doing so:
#
#   notebook_dir_for  <agents-dir> <notebook-dir> <notebook-dir-was-given> <agents-dir-was-given>
#   archive_dir_for   <agents-dir> <archive-dir>  <archive-dir-was-given>
#   notebook_roots_of <notebook-dir> <notebook-dir-was-given> <archive-dir> <archive-dir-was-given>
#   entries_in_root   <root>
#   notebook_entry_files_of <notebook-dir> <notebook-dir-was-given> <archive-dir> <archive-dir-was-given>
#
#   * `--agents-dir` moves the parent both defaults come from, and an explicit `--notebook-dir` still wins;
#   * the archive default is derived AFTER the flags are read, never before;
#   * `--archive-dir` given, or no `--notebook-dir` given → the archive root is read;
#   * `--notebook-dir` alone → the notebook only, so a suite stays sealed inside its fixture and cannot read
#     the live vault by accident. That last rule is the one worth keeping: a suite that pointed at a fixture
#     but still swept the real archive would read the fleet's own records into its cases.
#
# THE NAMES END IN `_of` DELIBERATELY. A caller that wants its own no-argument `notebook_roots` wrapper — as
# `wake-session.sh` does, wrapping its own flags — would otherwise shadow the library function it calls and
# recurse forever. Caught while writing the first version of this move.
#
# Works under /bin/bash 3.2 (macOS). Needs nothing but the shell and find.

notebook_dir_for() {  # <agents-dir> <notebook-dir> <notebook-dir-given> <agents-dir-given>
  if [ "${4:-0}" = 1 ] && [ "${3:-0}" = 0 ]; then
    printf '%s' "${1:-}/03.04 Records/Agent notebook"
  else
    printf '%s' "${2:-}"
  fi
}

archive_dir_for() {  # <agents-dir> <archive-dir> <archive-dir-given>
  if [ "${3:-0}" = 1 ]; then
    printf '%s' "${2:-}"
  else
    printf '%s' "${1:-}/03.09 Archive/Agent notebook"
  fi
}

notebook_roots_of() {  # <notebook-dir> <notebook-dir-given> <archive-dir> <archive-dir-given>
  [ -z "${1:-}" ] || printf '%s\n' "$1"
  if [ "${4:-0}" = 1 ] || [ "${2:-0}" = 0 ]; then
    [ -z "${3:-}" ] || printf '%s\n' "$3"
  fi
  return 0
}

# The entries under one root: `<root>/YYYY-MM/Agent session *.md`, one month folder down and no deeper. A
# folder note, a README or a rollup is not an entry, and neither is anything two folders down.
entries_in_root() {  # <root>
  nr_m=""
  for nr_m in "${1:-}"/[0-9][0-9][0-9][0-9]-[0-9][0-9]; do
    [ -d "$nr_m" ] && find "$nr_m" -mindepth 1 -maxdepth 1 -type f -name 'Agent session *.md' -print 2>/dev/null
  done
  return 0
}

notebook_entry_files_of() {  # the four root arguments; every entry path, sorted
  notebook_roots_of "$@" | while IFS= read -r nr_root; do
    [ -n "$nr_root" ] && [ -d "$nr_root" ] && entries_in_root "$nr_root"
  done | sort || true
}
