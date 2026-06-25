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
fail() { printf "  \033[31m✗\033[0m %s\n" "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

echo "Writing inventory dumps to $SCRIPT_DIR/"

# --- Homebrew ----------------------------------------------------------------
# Single Brewfile covers formulae + casks + taps + Mac App Store (via mas).
# `brew bundle dump --force` overwrites — which strips the `# group:` tags the
# installer relies on, plus any non-bundle (cargo/uv/npm) lines. We back up the
# tagged file first, then merge the tags back in (see merge-brewfile-tags.py).
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

# --- pipx --------------------------------------------------------------------
echo "pipx:"
if have pipx; then
  pipx list --short 2>/dev/null | sort > "$SCRIPT_DIR/pipx-list.txt"
  ok "pipx-list.txt ($(wc -l < "$SCRIPT_DIR/pipx-list.txt" | tr -d ' ') apps)"
else
  skip "pipx not on PATH"
fi

# --- uv tools ----------------------------------------------------------------
# `uv tool list` prints a per-tool block (name + version + deps). NO_COLOR
# strips uv's ANSI escapes so the dump is plain text and diff-friendly.
# Restoration uses `uv tool install <name>` per tool.
echo "uv tools:"
if have uv; then
  NO_COLOR=1 uv tool list 2>/dev/null > "$SCRIPT_DIR/uv-tools.txt"
  # Count lines that start with a non-space, non-dash character (the
  # "<name> v<ver>" header of each tool block).
  count=$(grep -cE '^[^[:space:]-]' "$SCRIPT_DIR/uv-tools.txt" 2>/dev/null || true)
  ok "uv-tools.txt (${count:-0} tools)"
else
  skip "uv not on PATH"
fi

# --- cargo install --globals -------------------------------------------------
# `cargo install --list` prints "<name> v<ver>:" headers followed by indented
# binary names. Count the headers.
echo "cargo:"
if have cargo; then
  cargo install --list 2>/dev/null > "$SCRIPT_DIR/cargo-list.txt"
  count=$(grep -cE ' v[0-9].*:$' "$SCRIPT_DIR/cargo-list.txt" 2>/dev/null || true)
  ok "cargo-list.txt (${count:-0} crates)"
else
  skip "cargo not on PATH"
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
