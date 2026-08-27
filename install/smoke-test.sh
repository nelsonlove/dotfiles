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

# 9. npm-globals.txt is well-formed. install_npm_globals splits each line into
#    `pkg flags` and passes $flags UNQUOTED to `npm install -g`, so a malformed
#    line is not a cosmetic problem: a second bare word in column 2 would be
#    handed to npm as an extra package to install.
NPMLIST="$DIR/npm-globals.txt"
if [[ ! -f "$NPMLIST" ]]; then
  bad "install/npm-globals.txt missing (the npm step reads it)"
else
  entries="$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$NPMLIST" | grep -v '^[[:space:]]*$')"
  # column 1: an npm package name, optionally @scoped
  badnames="$(printf '%s\n' "$entries" | awk '$1 !~ /^(@[A-Za-z0-9._~-]+\/)?[A-Za-z0-9._~-]+$/ { print $1 }')"
  # column 2+: flags only — a bare word here would silently become a package
  badflags="$(printf '%s\n' "$entries" | awk '{ for (i = 2; i <= NF; i++) if ($i !~ /^--?[A-Za-z]/) print $i }')"
  dupes="$(printf '%s\n' "$entries" | awk '{ print $1 }' | sort | uniq -d)"
  if   [[ -n "$badnames" ]]; then bad "npm-globals.txt: invalid package name(s): $(echo $badnames)"
  elif [[ -n "$badflags" ]]; then bad "npm-globals.txt: column 2+ must be flags, got: $(echo $badflags)"
  elif [[ -n "$dupes"    ]]; then bad "npm-globals.txt: duplicate entries: $(echo $dupes)"
  else ok "npm-globals.txt parses ($(printf '%s\n' "$entries" | wc -l | tr -d ' ') packages)"; fi
fi

# 10. the npm step is actually wired into install.sh (a valid list nothing runs
#     is the failure mode this catches), under system bash.
tmp="$(mktemp)"; sed '$d' "$INSTALL" > "$tmp"
cat >> "$tmp" <<T
NPM_GLOBALS="$NPMLIST"
case " \$STEPS " in *" npm "*) ;; *) echo ERR-npm-not-a-step; exit 3;; esac
type install_npm_globals >/dev/null 2>&1 || { echo ERR-no-install_npm_globals; exit 3; }
# the parse helper must round-trip the list without losing or inventing lines
want="\$(sed -e 's/#.*//' -e 's/[[:space:]]*\$//' "\$NPM_GLOBALS" | grep -cv '^[[:space:]]*\$')"
got="\$(npm_globals_entries | grep -c .)"
[ "\$want" = "\$got" ] || { echo "ERR-entry-count want=\$want got=\$got"; exit 3; }
# --no-packages must suppress npm too, or it installs during a config-only run
SKIP_STEPS=" packages npm "; ONLY_STEPS=""
step_enabled npm && { echo ERR-no-packages-leaves-npm-on; exit 3; }
DRY_RUN=0; ONLY_STEPS=" npm "; SKIP_STEPS=""
plan="\$(print_step_plan 2>/dev/null)"
case "\$plan" in *"npm —"*) ;; *) echo ERR-plan-missing-npm; exit 3;; esac
case "\$plan" in *"packages —"*) echo ERR-plan-shows-excluded-packages; exit 3;; esac
echo NPM_OK
T
if "$SH" "$tmp" 2>/dev/null | grep -q NPM_OK; then ok "npm step wired in (STEPS, plan, --no-packages, list parse)"; else bad "npm step failed: $("$SH" "$tmp" 2>&1 | grep -E '^ERR' | head -1)"; fi
rm -f "$tmp"

echo
[[ $rc == 0 ]] && echo "smoke test PASSED" || echo "smoke test FAILED"
exit $rc
