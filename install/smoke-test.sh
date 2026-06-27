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

echo
[[ $rc == 0 ]] && echo "smoke test PASSED" || echo "smoke test FAILED"
exit $rc
