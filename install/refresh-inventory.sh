#!/usr/bin/env bash
# Dump declarative inventory for surfaces tracked in REPRODUCIBILITY.md.
# Run from anywhere; outputs land next to this script in install/.
# Idempotent: each tool either writes its file or reports "skipped".
# Review `git diff install/` after running, then commit if you want.

set -uo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR" || exit 1

ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
skip() { printf "  \033[33m-\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

# merge_pkg_list <listfile> <observed-names-file> <noun>
# <observed-names-file> must be LC_ALL=C sorted and unique.
#
# NOTE it cannot resolve a `from=?`: <observed> holds names, and a name already
# present in the file is excluded from `added`, so its line is copied through
# verbatim. Recording a source is a hand-edit; `pipx list --json` reports each
# app's `main_package.package_or_url`, which is where the real path comes from.
merge_pkg_list() {
  local out="$1" observed="$2" noun="$3"
  local prev names header added n
  prev="$(mktemp -t pkglist.prev.XXXXXX)"
  names="$(mktemp -t pkglist.names.XXXXXX)"
  header="$(mktemp -t pkglist.hdr.XXXXXX)"
  # existing entries as name<TAB>rest; the file may not exist yet. The comment
  # stripper is anchored on whitespace-or-start so a `from=…#ref` git pin keeps
  # its fragment instead of being silently truncated to the default branch.
  sed -e 's/[[:space:]]#.*//' -e 's/^#.*//' -e 's/[[:space:]]*$//' "$out" 2>/dev/null \
    | awk 'NF { name = $1; $1 = ""; sub(/^[[:space:]]+/, ""); print name "\t" $0 }' \
    | LC_ALL=C sort -u > "$prev"
  cut -f1 "$prev" | LC_ALL=C sort -u > "$names"
  added="$(LC_ALL=C comm -13 "$names" "$observed")"
  # the leading `#` block is the file's documentation — keep it verbatim
  awk '/^[[:space:]]*#/ { print; next } { exit }' "$out" 2>/dev/null > "$header"
  # `if`, not `[ -n "$added" ] && …`: a false AND-list exits 1, which under
  # `set -o pipefail` propagates out of the group and skips the mv entirely —
  # leaving a stray .tmp and reporting success for a write that never happened.
  # That is the exact failure this whole change set exists to remove.
  if {
       [ -s "$header" ] && { cat "$header"; echo; }
       {
         cat "$prev"
         if [ -n "$added" ]; then printf '%s\n' "$added" | sed 's/$/\t/'; fi
       } | LC_ALL=C sort -u -k1,1 \
         | awk -F'\t' '{ if ($2 != "") printf "%s  %s\n", $1, $2; else print $1 }'
     } > "$out.tmp" && [ -s "$out.tmp" ] && mv "$out.tmp" "$out"; then
    n=$(grep -cvE '^[[:space:]]*(#|$)' "$out")
    if [ -n "$added" ]; then
      ok "$(basename "$out") ($n $noun; added: $(printf '%s' "$added" | tr '\n' ' '))"
    else
      ok "$(basename "$out") ($n $noun; nothing new on this machine)"
    fi
  else
    rm -f "$out.tmp"
    fail "$(basename "$out") — merge failed; file left unchanged"
  fi
  rm -f "$prev" "$names" "$header"
}

# install/smoke-test.sh sources this file with REFRESH_LIB_ONLY=1 to exercise
# merge_pkg_list without running any dumps. Everything past here does real work.
if [ -n "${REFRESH_LIB_ONLY:-}" ]; then return 0 2>/dev/null || exit 0; fi

echo "Writing inventory dumps to $SCRIPT_DIR/"

# --- Homebrew ----------------------------------------------------------------
# Single Brewfile covers formulae + casks + taps + Mac App Store (via mas).
# `brew bundle dump --force` overwrites — which strips the `# group:` tags the
# installer relies on, plus any non-bundle (cargo/uv) lines. We back up the
# tagged file first, then merge the tags back in (see merge-brewfile-tags.py).
# npm globals used to ride along here too; they now live in npm-globals.txt,
# which is the only one of these lists an installer actually consumes.
echo "Homebrew:"
if have brew; then
  bak="$(mktemp -t Brewfile.prev.XXXXXX)"
  [[ -f "$SCRIPT_DIR/Brewfile" ]] && cp "$SCRIPT_DIR/Brewfile" "$bak"
  if brew bundle dump --force --file="$SCRIPT_DIR/Brewfile" >/dev/null 2>&1; then
    if [[ -s "$bak" ]] && have python3; then
      python3 "$SCRIPT_DIR/merge-brewfile-tags.py" "$bak" "$SCRIPT_DIR/Brewfile"
      ok "Brewfile (formulae + casks + taps + mas; group tags preserved)"
    else
      warn "Brewfile dumped WITHOUT tag merge (no prior tags or python3 missing)"
    fi
  else
    fail "brew bundle dump failed"
  fi
  rm -f "$bak"
else
  skip "brew not on PATH"
fi

# --- language packages: pipx / uv / cargo / npm -------------------------------
# One tracked list per tool, all the same shape (see install/pipx-list.txt for
# the format). These MERGE rather than overwrite, which is a bug fix, not a
# nicety: pipx, uv and cargo all report zero packages on the MacBook Air while
# the MacBook Pro has a dozen, so the previous `tool list > file` dumps
# truncated all three files to empty whenever the refresh ran on the Air — and
# reported success while doing it.
#
# So: ADD what is newly installed on this machine, PRESERVE the existing
# `from=` and flag columns (no dump can rediscover those), never REMOVE.
# Dropping a package — or resolving a `from=?` — is a deliberate hand-edit.

echo "pipx:"
if have pipx; then
  obs="$(mktemp -t pkglist.obs.XXXXXX)"
  pipx list --short 2>/dev/null | awk 'NF { print $1 }' | LC_ALL=C sort -u > "$obs"
  merge_pkg_list "$SCRIPT_DIR/pipx-list.txt" "$obs" apps
  rm -f "$obs"
else
  skip "pipx not on PATH"
fi

# `uv tool list` prints a `<name> v<ver>` header per tool, then indented deps.
# NO_COLOR strips uv's ANSI escapes so the parse sees plain text.
echo "uv tools:"
if have uv; then
  obs="$(mktemp -t pkglist.obs.XXXXXX)"
  NO_COLOR=1 uv tool list 2>/dev/null | awk '/^[^[:space:]-]/ { print $1 }' | LC_ALL=C sort -u > "$obs"
  merge_pkg_list "$SCRIPT_DIR/uv-tools.txt" "$obs" tools
  rm -f "$obs"
else
  skip "uv not on PATH"
fi

# `cargo install --list` prints "<name> v<ver>:" headers, then indented binaries.
echo "cargo:"
if have cargo; then
  obs="$(mktemp -t pkglist.obs.XXXXXX)"
  cargo install --list 2>/dev/null | awk '/^[^[:space:]]/ { sub(/:$/, "", $1); print $1 }' | LC_ALL=C sort -u > "$obs"
  merge_pkg_list "$SCRIPT_DIR/cargo-list.txt" "$obs" crates
  rm -f "$obs"
else
  skip "cargo not on PATH"
fi

# `npm ls -g --depth=0 --parseable` prints one install path per top-level
# package; the name is everything after the last `node_modules/`, which keeps
# `@scope/name` intact. Skipped: package managers Homebrew owns (the node and
# pnpm formulae ship them). Managing those through `npm -g` makes the two
# package managers fight over the same files.
NPM_SKIP=" npm pnpm corepack yarn "
echo "npm globals:"
if have npm; then
  obs="$(mktemp -t pkglist.obs.XXXXXX)"
  npm ls -g --depth=0 --parseable 2>/dev/null \
    | sed -n 's|.*/node_modules/||p' \
    | while IFS= read -r p; do case "$NPM_SKIP" in *" $p "*) ;; *) [ -n "$p" ] && echo "$p";; esac; done \
    | LC_ALL=C sort -u > "$obs"
  merge_pkg_list "$SCRIPT_DIR/npm-globals.txt" "$obs" packages
  rm -f "$obs"
else
  skip "npm not on PATH"
fi

# --- mas (Mac App Store) -----------------------------------------------------
# Covered by `brew bundle dump`. We don't write a separate mas-list.txt — see
# REPRODUCIBILITY.md "Per-surface notes / Mac App Store" for rationale.
# But: warn if mas isn't installed, since the Brewfile MAS lines depend on it.
echo "mas:"
if have mas; then
  ok "mas present — Brewfile includes Mac App Store entries"
else
  skip "mas not installed — Brewfile will not include Mac App Store apps"
fi

echo
echo "Done. Review with:"
echo "  git -C $(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/..") diff install/"
