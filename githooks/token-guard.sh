#!/usr/bin/env bash
# token-guard.sh — refuse a GitHub token, or a regular file at claude/settings.local.json, before it reaches
# this repository's history. This repository is PUBLIC.
#
#   token-guard.sh --staged                        what the pre-commit hook runs: the index about to be committed
#   token-guard.sh --range <base> <head> [--repo <dir>]
#                                                  what CI runs on a pull request: the tree at <head>, and every
#                                                  line added by every commit in <base>..<head>
#   token-guard.sh --history <head> [--repo <dir>] the same over every commit reachable from <head>: CI's fallback
#                                                  when a push's base cannot be read
#
# It refuses when:
#   * claude/settings.local.json is present as anything but a symlink (git mode 120000). In this repo it must
#     be a symlink into 09.11 Secrets; the real file holds secrets and lives outside the repo;
#   * any content matches a GitHub token: `ghp_`, `gho_`, `ghu_`, `ghs_` or `ghr_` and 36 letters or digits,
#     or a fine-grained one (`github_pat_` and 20 or more letters, digits or underscores).
# It says why and names the path. Exit 1 on a refusal, 2 on bad usage, 0 when clean.
#
# WHY IT EXISTS (Nelson's "C", 2026-09-29). Between 2026-09-22 09:12 and 2026-09-29, claude/settings.local.json
# in the main checkout was a regular 207-byte file holding a plaintext GitHub token, in this public repo.
# Nothing reached history. The rear admiral restored the symlink.
#
# THE CAUSE IS INFERRED, NOT PROVED (the captain's findings, 2026-09-29):
# Claude Code's settings writer is believed to replace a symlinked settings.local.json with a regular file
# (inferred 2026-09-29, not proved); this guard is the only defence.
#   * The link was gone between 2026-09-14T21:49Z and 23:08Z: a token write at 23:08Z did not reach the 09.11
#     target.
#   * The likely first cause is a permission "always allow" write (about 65% sure; transcripts do not record
#     permission clicks).
#   * The 2026-09-22 09:12 mtime came from `git pull --autostash` (session 3d726e64), which rewrote the file
#     fresh (about 90% sure). That is why post-merge and post-checkout also warn.
#
# The local hook can be skipped with `git commit --no-verify`. The CI check on every pull request cannot.
set -u

SETTINGS="claude/settings.local.json"
# The patterns are built from parts so this file does not match itself.
# gh[pousr]_: the classic personal token (p), the OAuth token `gh auth` holds (o), user-to-server (u),
# server-to-server (s) and refresh (r) tokens (review 1 of #74: this machine's GITHUB_PERSONAL_ACCESS_TOKEN
# is a `gho_` token).
P_CLASSIC="gh""[pousr]_[A-Za-z0-9]{36}"
P_FINE="github""_pat_[A-Za-z0-9_]{20,}"
PATTERN="$P_CLASSIC|$P_FINE"

refused=0
refuse() { refused=1; printf 'token-guard: refused: %s\n' "$*" >&2; }

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

mode="${1:-}"; [ -n "$mode" ] || usage; shift
repo="."
case "$mode" in
  --staged) ;;
  --range)
    [ $# -ge 2 ] || usage
    base="$1"; head="$2"; shift 2
    [ -n "$base" ] && [ -n "$head" ] || { printf 'token-guard: --range needs a base and a head, both non-empty\n' >&2; exit 2; }
    revs="$base..$head"
    ;;
  --history)
    [ $# -ge 1 ] || usage
    head="$1"; base=""; shift
    [ -n "$head" ] || { printf 'token-guard: --history needs a head\n' >&2; exit 2; }
    revs="$head"
    ;;
  *) usage ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || usage; repo="$2"; shift 2 ;;
    *) usage ;;
  esac
done
g() { git -C "$repo" "$@"; }

if [ "$mode" = --staged ]; then
  # 1. The settings file, as the index holds it now (only when this commit touches it).
  if [ -n "$(g diff --cached --name-only --diff-filter=ACMRT -- "$SETTINGS")" ]; then
    m=$(g ls-files -s -- "$SETTINGS" | awk '{print $1}')
    if [ -n "$m" ] && [ "$m" != 120000 ]; then
      refuse "$SETTINGS is staged as mode $m, not a symlink (120000). It must be a symlink into 09.11 Secrets, because the real file holds a GitHub token and this repo is public. Unstage it: git restore --staged $SETTINGS"
    fi
  fi
  # 2. Every staged file's content, whole (a token already in a file you touch is a leak too).
  while IFS= read -r -d '' f; do
    if g cat-file -p ":$f" 2>/dev/null | grep -aqE "$PATTERN"; then
      refuse "$f contains what looks like a GitHub token. Remove it from the file and unstage it; never commit a token to this public repo."
    fi
  done < <(g diff --cached --name-only --diff-filter=ACMRT -z)
else
  if [ -n "$base" ]; then
    g rev-parse --verify -q "$base^{commit}" >/dev/null || { printf 'token-guard: cannot read base %s\n' "$base" >&2; exit 2; }
  fi
  g rev-parse --verify -q "$head^{commit}" >/dev/null || { printf 'token-guard: cannot read head %s\n' "$head" >&2; exit 2; }
  # 1. The settings file in the tree at head.
  m=$(g ls-tree "$head" -- "$SETTINGS" | awk '{print $1}')
  if [ -n "$m" ] && [ "$m" != 120000 ]; then
    refuse "$SETTINGS is mode $m at $head, not a symlink (120000). It must be a symlink into 09.11 Secrets."
  fi
  # 2. Every file in the tree at head.
  # git grep exits 1 for "no match" and 2 or more for an error; an error must never read as a clean tree
  # (review 1 of #74).
  hits=$(g -c core.quotePath=false grep -I -l -E "$PATTERN" "$head" --); grc=$?
  if [ "$grc" -ge 2 ]; then
    printf 'token-guard: git grep failed on the tree at %s (exit %s); refusing to call it clean\n' "$head" "$grc" >&2
    exit 2
  fi
  while IFS= read -r f; do
    [ -n "$f" ] && refuse "${f#"$head":} at $head contains what looks like a GitHub token."
  done <<< "$hits"
  # 3. Every line added by any commit in the range (or, with --history, in all of the head's history), so a token added and later removed still counts: it is
  # in the history the pull request would publish.
  # One pass: awk tags each ADDED line with its file, and one grep keeps the matches. Only the file names are
  # printed, never the matching text. Hardened on review 1 of #74:
  #   * core.quotePath=false, so a non-ASCII name is not quoted; a name git still quotes is refused anyway,
  #     under the placeholder, because an empty name must never drop a line;
  #   * a `+++` line counts as a file header only BEFORE the first hunk of a file, so an added line that
  #     starts with `++ ` is content, not a header;
  #   * --src-prefix/--dst-prefix fix the `b/` the parser reads, whatever diff.noprefix says (review 2);
  #   * --diff-merges=first-parent shows what a merge commit adds, so a token added while resolving a merge
  #     is seen.
  while IFS= read -r f; do
    [ -n "$f" ] && refuse "$f gains a line that looks like a GitHub token in $revs (history counts, even if a later commit removes it)."
  done < <(g -c core.quotePath=false log -p --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ --diff-merges=first-parent --format= "$revs" -- \
             | awk '/^diff --git /{hunk=0; f="(a file whose name git quotes)"; next}
                    !hunk && /^\+\+\+ /{ if (substr($0,5,2)=="b/") f=substr($0,7); next }
                    /^@@ /{hunk=1; next}
                    hunk && /^\+/{print f "\t" substr($0,2)}' \
             | grep -aE "	.*($PATTERN)" | cut -f1 | sort -u)
fi

[ "$refused" = 0 ] || exit 1
exit 0
