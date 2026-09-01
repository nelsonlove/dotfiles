#!/usr/bin/env bash
# Smoke-test install.sh under macOS's SYSTEM bash (/bin/bash, currently 3.2) to
# catch bash-4-only features (associative arrays, mapfile, ${x^^}, …) before
# they reach a fresh machine — that's where install.sh actually runs, before
# Homebrew installs a newer bash.
#
# The harness itself can run under any bash; it explicitly invokes /bin/bash
# for the checks. Run:  install/smoke-test.sh   (exits non-zero on failure)

set -uo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
INSTALL="$DIR/install.sh"
BREWFILE="$DIR/Brewfile"
SH=/bin/bash
rc=0
ok()  { printf "  \033[32mok\033[0m   %s\n" "$1"; }
bad() { printf "  \033[31mFAIL\033[0m %s\n" "$1"; rc=1; }

if [[ ! -x "$SH" ]]; then echo "no $SH — skipping (not macOS?)"; exit 0; fi
echo "Testing install.sh under $("$SH" --version | head -1)"

# 1. parses under system bash
if "$SH" -n "$INSTALL" 2>/dev/null; then ok "parses under /bin/bash"; else bad "syntax error under /bin/bash"; fi

# 2. loads + --help runs under system bash (this is what the declare -A bug broke)
if "$SH" "$INSTALL" --help >/dev/null 2>/tmp/smoke.$$; then
  ok "loads + --help runs under /bin/bash"
else
  bad "load failed under /bin/bash: $(head -1 /tmp/smoke.$$ 2>/dev/null)"
fi
rm -f "/tmp/smoke.$$"

# 3. menu/selection logic under system bash, with no link_configs/brew side effects
tmp="$(mktemp)"; sed '$d' "$INSTALL" > "$tmp"   # strip the trailing `main "$@"`
cat >> "$tmp" <<T
BREWFILE="$BREWFILE"
[ "\$(group_index shell)" -ge 0 ] || { echo ERR-group_index-known; exit 3; }
[ "\$(group_index nope)" = -1 ] || { echo ERR-group_index-unknown; exit 3; }
for g in "\${DEFAULT_ON[@]}"; do SEL[\$(group_index "\$g")]=1; done
sl=" \$(selected_list) "
case "\$sl" in *" core "*) ;; *) echo ERR-no-core; exit 3;; esac
case "\$sl" in *" shell "*) ;; *) echo ERR-no-shell; exit 3;; esac
print_menu >/dev/null 2>&1 || { echo ERR-print_menu; exit 3; }
echo SMOKE_OK
T
if "$SH" "$tmp" 2>/dev/null | grep -q SMOKE_OK; then ok "menu/selection logic runs under /bin/bash"; else bad "menu/selection logic failed under /bin/bash"; fi
rm -f "$tmp"

# 4. every Brewfile group tag is covered by the menu (GROUP_ORDER) or core/_dep/_untagged
known="core _dep _untagged $(grep -oE 'GROUP_ORDER=\(([^)]*)\)' "$INSTALL" | sed -E 's/GROUP_ORDER=\(//; s/\)//')"
missing=""
for g in $(grep -oE '# group:[a-z_-]+' "$BREWFILE" | sed 's/# group://' | sort -u); do
  case " $known " in *" $g "*) ;; *) missing="$missing $g";; esac
done
[[ -z "$missing" ]] && ok "all Brewfile group tags covered by the menu" || bad "Brewfile groups missing from GROUP_ORDER:$missing"

# 5. no untagged Brewfile entries
n="$(grep -E '^(brew|cask|mas) ' "$BREWFILE" | grep -vcE '# group:')"
[[ "$n" == 0 ]] && ok "no untagged Brewfile entries" || bad "$n untagged Brewfile entries"

# 6. static scan for bash-4-only constructs (catches the regression class even
#    when it would only soft-fail at runtime — the original declare -A bug)
b4="$(grep -nE 'declare[[:space:]]+-A|local[[:space:]]+-A|\bmapfile\b|\breadarray\b|\$\{[^}]*(\^\^|,,)|\[-[0-9]' "$INSTALL" || true)"
[[ -z "$b4" ]] && ok "no bash-4-only constructs (declare -A, mapfile, \${x^^}, …)" || bad "bash-4-only construct(s):
$(printf '%s\n' "$b4" | sed 's/^/      /')"

# 7. bundle resolution (compute_bundle / preview / browse) under system bash.
#    Guards the empty-description regression: entries with no `# desc` comment
#    must still emit their full raw line (blank lines = silently-dropped packages,
#    and a whitespace field separator would shift the raw line off the row).
tmp="$(mktemp)"; gen="$(mktemp)"; sed '$d' "$INSTALL" > "$tmp"
cat >> "$tmp" <<T
BREWFILE="$BREWFILE"
INCLUDE_STALE=1
skip="\$(compute_bundle "core \${GROUP_ORDER[*]}" "$gen")"
blanks="\$(grep -c '^\$' "$gen")"
[ "\$blanks" = 0 ] || { echo "ERR-blank-lines=\$blanks"; exit 3; }
# a mas entry that has no description must still carry its "id:" arg
grep -qE '^mas "[^"]+", id: [0-9]+' "$gen" || { echo ERR-mas-id-lost; exit 3; }
# every emitted brew/cask/mas line must resolve to a real Brewfile line
while IFS= read -r l; do grep -qxF "\$l" "$BREWFILE" || { echo "ERR-fabricated: \$l"; exit 3; }; done < <(grep -E '^(brew|cask|mas) ' "$gen")
preview_plan "core shell" >/dev/null 2>&1 || { echo ERR-preview; exit 3; }
browse_group shell </dev/null >/dev/null 2>&1 || { echo ERR-browse; exit 3; }
echo BUNDLE_OK
T
if "$SH" "$tmp" 2>/dev/null | grep -q BUNDLE_OK; then ok "bundle resolution intact (no dropped/fabricated lines; review & browse run)"; else bad "bundle resolution failed: $("$SH" "$tmp" 2>&1 | grep -E '^ERR' | head -1)"; fi
rm -f "$tmp" "$gen"

# 8. step scoping (--only / --skip) and the step plan, under system bash.
tmp="$(mktemp)"; sed '$d' "$INSTALL" > "$tmp"
cat >> "$tmp" <<'T'
ONLY_STEPS=" links "; SKIP_STEPS=""
step_enabled links    || { echo ERR-only-links-enabled; exit 3; }
step_enabled packages && { echo ERR-only-links-excludes-packages; exit 3; }
ONLY_STEPS=""; SKIP_STEPS=" packages "
step_enabled packages && { echo ERR-skip-packages-still-on; exit 3; }
step_enabled shell    || { echo ERR-skip-hit-wrong-step; exit 3; }
DRY_RUN=0; ONLY_STEPS=" links "; SKIP_STEPS=""
# Capture via command substitution, not `| grep -q`: under `set -o pipefail` a
# grep -q that exits early would SIGPIPE print_step_plan and fail the pipeline.
plan="$(print_step_plan 2>/dev/null)"
case "$plan" in *"links —"*) ;;    *) echo ERR-plan-missing-links; exit 3;; esac
case "$plan" in *"packages —"*) echo ERR-plan-shows-excluded-packages; exit 3;; esac
echo STEP_OK
T
if "$SH" "$tmp" 2>/dev/null | grep -q STEP_OK; then ok "step scoping (--only/--skip) + step plan run under /bin/bash"; else bad "step scoping failed: $("$SH" "$tmp" 2>&1 | grep -E '^ERR' | head -1)"; fi
rm -f "$tmp"

# 9. every language-package list is well-formed. install_pkg_list word-splits
#    the tokens after the package name and passes the flag ones UNQUOTED to the
#    tool, so a malformed line is not cosmetic: a stray bare word in column 2
#    would be handed over as an extra package to install.
for LIST in npm-globals.txt pipx-list.txt uv-tools.txt cargo-list.txt; do
  F="$DIR/$LIST"
  if [[ ! -f "$F" ]]; then bad "install/$LIST missing (a language-package step reads it)"; continue; fi
  # same comment stripper as install.sh's pkg_list_entries, so this test sees
  # exactly what the installer will
  entries="$(sed -e 's/[[:space:]]#.*//' -e 's/^#.*//' -e 's/[[:space:]]*$//' "$F" | grep -v '^[[:space:]]*$')"
  # column 1: a package name, optionally @scoped (npm)
  badnames="$(printf '%s\n' "$entries" | awk '$1 !~ /^(@[A-Za-z0-9._~-]+\/)?[A-Za-z0-9._~-]+$/ { print $1 }')"
  # column 2+: only `from=…` or a flag. Anything else would become a package.
  badtok="$(printf '%s\n' "$entries" | awk '{ for (i = 2; i <= NF; i++) if ($i !~ /^from=/ && $i !~ /^--?[A-Za-z]/) print $i }')"
  # at most one from= per line, or the last one silently wins
  multifrom="$(printf '%s\n' "$entries" | awk '{ n = 0; for (i = 2; i <= NF; i++) if ($i ~ /^from=/) n++; if (n > 1) print $1 }')"
  dupes="$(printf '%s\n' "$entries" | awk '{ print $1 }' | sort | uniq -d)"
  if   [[ -n "$badnames"  ]]; then bad "$LIST: invalid package name(s): $(echo $badnames)"
  elif [[ -n "$badtok"    ]]; then bad "$LIST: column 2+ must be from=… or a flag, got: $(echo $badtok)"
  elif [[ -n "$multifrom" ]]; then bad "$LIST: more than one from= on: $(echo $multifrom)"
  elif [[ -n "$dupes"     ]]; then bad "$LIST: duplicate entries: $(echo $dupes)"
  else ok "$LIST parses ($(printf '%s\n' "$entries" | wc -l | tr -d ' ') entries)"; fi
done

# 10. the four language-package steps are wired into install.sh (a valid list
#     that nothing runs is the failure mode this catches), under system bash.
tmp="$(mktemp)"; sed '$d' "$INSTALL" > "$tmp"
cat >> "$tmp" <<T
# Point SCRIPT_DIR at the real install/ dir: the harness runs a copy of
# install.sh from mktemp, where SCRIPT_DIR would otherwise resolve to /var/…/T
# and every pkg_list_file() would name a nonexistent path — making the
# round-trip assertion below compare 0 to 0 and pass unconditionally.
SCRIPT_DIR="$DIR"
T
cat >> "$tmp" <<'T'
for t in npm pipx uv cargo; do
  case " $STEPS " in *" $t "*) ;; *) echo "ERR-$t-not-a-step"; exit 3;; esac
  [ -n "$(pkg_list_file "$t")" ]  || { echo "ERR-$t-no-file";  exit 3; }
  [ -n "$(pkg_list_label "$t")" ] || { echo "ERR-$t-no-label"; exit 3; }
  # the parse helper must round-trip its list without losing or inventing lines
  f="$(pkg_list_file "$t")"
  [ -f "$f" ] || { echo "ERR-$t-file-missing: $f"; exit 3; }
  want="$(sed -e 's/[[:space:]]#.*//' -e 's/^#.*//' -e 's/[[:space:]]*$//' "$f" | grep -cv '^[[:space:]]*$')"
  got="$(pkg_list_entries "$t" | grep -c .)"
  [ "$want" -gt 0 ] || { echo "ERR-$t-no-entries (assertion would be vacuous)"; exit 3; }
  [ "$want" = "$got" ] || { echo "ERR-$t-entry-count want=$want got=$got"; exit 3; }
  # --no-packages must suppress every one of them
  SKIP_STEPS=" packages npm pipx uv cargo "; ONLY_STEPS=""
  step_enabled "$t" && { echo "ERR-no-packages-leaves-$t-on"; exit 3; }
  DRY_RUN=0; ONLY_STEPS=" $t "; SKIP_STEPS=""
  plan="$(print_step_plan 2>/dev/null)"
  case "$plan" in *"$t —"*) ;; *) echo "ERR-plan-missing-$t"; exit 3;; esac
  case "$plan" in *"packages —"*) echo "ERR-plan-shows-excluded-packages"; exit 3;; esac
done
type install_pkg_list >/dev/null 2>&1 || { echo ERR-no-install_pkg_list; exit 3; }
# a `from=…#ref` git pin must survive comment-stripping: an unanchored
# `s/#.*//` would silently turn a pinned ref into the default branch.
pin="$(mktemp)"
printf 'foo  from=github:u/r#v1.2.3  --save-exact\n# whole-line comment\nbar  from=x  # trailing comment\n' > "$pin"
pkg_list_file() { echo "$pin"; }
got="$(pkg_list_entries npm)"
case "$got" in *'#v1.2.3'*) ;; *) echo "ERR-git-pin-stripped: $got"; rm -f "$pin"; exit 3;; esac
case "$got" in *'trailing comment'*) echo "ERR-trailing-comment-kept: $got"; rm -f "$pin"; exit 3;; esac
[ "$(printf '%s\n' "$got" | grep -c .)" = 2 ] || { echo "ERR-pin-entry-count: $got"; rm -f "$pin"; exit 3; }
rm -f "$pin"
echo PKG_OK
T
if "$SH" "$tmp" 2>/dev/null | grep -q PKG_OK; then ok "npm/pipx/uv/cargo steps wired in (STEPS, plan, --no-packages, list parse)"; else bad "language-package steps failed: $("$SH" "$tmp" 2>&1 | grep -E '^ERR' | head -1)"; fi
rm -f "$tmp"

# 11. the Brewfile carries no non-bundle lines. These looked declarative for a
#     long time and installed nothing; keep them from creeping back.
nb="$(grep -nE '^(cargo|uv|npm|pnpm|gem) ' "$BREWFILE" || true)"
[[ -z "$nb" ]] && ok "no dead non-bundle lines in the Brewfile" || bad "non-bundle line(s) in Brewfile — brew bundle never installs these:
$(printf '%s\n' "$nb" | sed 's/^/      /')"

# 12. refresh-inventory.sh's merge must WRITE even when it finds nothing new,
#     and must not leave a .tmp behind. This is the regression that shipped:
#     `[ -n "$added" ] && …` as a pipeline's first stage exits 1 when $added is
#     empty, which under `set -o pipefail` skipped the mv — so the file was
#     never rewritten while a green ✓ claimed it was. An idempotence check
#     cannot catch that (unchanged file looks identical either way); asserting
#     on the .tmp and on a known normalisation can.
REFRESH="$DIR/refresh-inventory.sh"
if [[ ! -f "$REFRESH" ]]; then
  bad "install/refresh-inventory.sh missing"
else
  wd="$(mktemp -d)"
  # deliberately mis-spaced so a real rewrite is observable in the output
  printf '# hdr\n\nbeta\t\nalpha   from=x\n' | tr '\t' ' ' > "$wd/list.txt"
  : > "$wd/observed"        # nothing installed -> $added empty -> the bug case
  # SC1090: $REFRESH is built from $DIR at runtime, so shellcheck cannot follow
  # it. The source= directive names the file for anyone reading, and the disable
  # keeps the CI shellcheck job green.
  # shellcheck source=install/refresh-inventory.sh disable=SC1090
  ( set -uo pipefail
    REFRESH_LIB_ONLY=1 . "$REFRESH"
    merge_pkg_list "$wd/list.txt" "$wd/observed" things ) > "$wd/log" 2>&1
  leftover="$(ls "$wd"/*.tmp 2>/dev/null || true)"
  if [[ -n "$leftover" ]]; then
    bad "merge_pkg_list left a .tmp behind (the write was skipped): $leftover"
  elif grep -q 'merge failed' "$wd/log"; then
    bad "merge_pkg_list reported failure on a no-new-packages run: $(cat "$wd/log")"
  elif ! grep -qx 'alpha  from=x' "$wd/list.txt"; then
    bad "merge_pkg_list did not rewrite the file (normalisation absent): $(cat "$wd/list.txt")"
  elif ! grep -qx '# hdr' "$wd/list.txt"; then
    bad "merge_pkg_list dropped the header comment block"
  else
    ok "merge writes (and cleans up) when nothing new is installed"
  fi
  rm -rf "$wd"
fi

echo
[[ $rc == 0 ]] && echo "smoke test PASSED" || echo "smoke test FAILED"
exit $rc
