#!/bin/bash
# Tests for vault-mcp-remote-update/run.sh and _lib/notice.sh. Throwaway git repos under /tmp; the notice goes to a stub (NOTICE_CMD), never to the screen.
set -u
here=$(cd "$(dirname "$0")" && pwd -P); RUN="$here/../run.sh"; NOTICE="$here/../../_lib/notice.sh"
pass=0; fail=0; failed=""
ROOT=$(mktemp -d /tmp/vmru-tests.XXXXXX); trap '/usr/bin/trash "$ROOT" 2>/dev/null' EXIT
check() { n="$1"; shift; if "$@"; then pass=$((pass+1)); else fail=$((fail+1)); failed="$failed\n  - $n"; printf 'FAIL %s\n---\n%s\n---\n' "$n" "$OUT"; fi; }
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }
g() { git -C "$1" -c user.name=t -c user.email=t@example.invalid "${@:2}"; }

new_case() {
  C=$(mktemp -d "$ROOT/case.XXXXXX")
  g "$ROOT" init -q --bare "$C/origin.git" 2>/dev/null || git init -q --bare "$C/origin.git"
  git init -q -b main "$C/seed"; g "$C/seed" commit -q --allow-empty -m one; g "$C/seed" remote add origin "$C/origin.git"; g "$C/seed" push -q origin main
  git clone -q "$C/origin.git" "$C/proxy"
  mkdir -p "$C/cfg"; echo "vault.example.invalid" > "$C/cfg/public-hostname"
  printf '<plist><string>set -a; exec node %s/packages/server/dist/front.js</string></plist>\n' "$C/proxy" > "$C/agent.plist"
  printf '#!/bin/bash\nprintf "%%s|%%s\\n" "$1" "$2" >> "%s/shown"\nexit "$(cat "%s/notice_rc" 2>/dev/null || echo 0)"\n' "$C" "$C" > "$C/notice-stub"; chmod +x "$C/notice-stub"
}
ahead() { g "$C/seed" commit -q --allow-empty -m "$1"; g "$C/seed" push -q origin main; }
go() { OUT=$(env -i HOME="$C" PATH=/usr/bin:/bin VAULT_MCP_PLIST="$C/agent.plist" VAULT_MCP_HOST_FILE="$C/cfg/public-hostname" VAULT_MCP_STATE_DIR="$C/state" NOTICE_CMD="$C/notice-stub" NOTICE_STATE_DIR="$C/nstate" /bin/bash "$RUN" 2>&1); RC=$?; }

new_case; go
check "even: exit 0" [ "$RC" = 0 ]; check "even: no notice" [ ! -f "$C/shown" ]
new_case; ahead "two: fix things"; go
check "behind: exit 0" [ "$RC" = 0 ]; check "behind: notice" grep -qF '1 behind' "$C/shown"
check "behind: names the host from config" grep -qF 'vault.example.invalid' "$C/nstate/vault-mcp-remote/latest-notice.md"
check "behind: rev recorded" [ -s "$C/state/drift-notified-rev" ]
go; check "same rev: no second notice" [ "$(wc -l < "$C/shown" | tr -d ' ')" = 1 ]
ahead "three"; go; check "new rev: notice again" [ "$(wc -l < "$C/shown" | tr -d ' ')" = 2 ]
new_case; ahead "two"; echo 1 > "$C/notice_rc"; go
check "notice fails: exit 1" [ "$RC" = 1 ]; check "notice fails: rev not recorded" [ ! -f "$C/state/drift-notified-rev" ]
new_case; /usr/bin/trash "$C/cfg/public-hostname"; go
check "no host file: exit 1" [ "$RC" = 1 ]; check "no host file: says which file" has "public-hostname is missing"
new_case; : > "$C/cfg/public-hostname"; go
check "empty host file: exit 1" [ "$RC" = 1 ]
new_case; printf '<plist><string>exec node /nonexistent/old-repo/packages/server/dist/front.js</string></plist>\n' > "$C/agent.plist"; go
check "dead checkout path: exit 1" [ "$RC" = 1 ]; check "dead checkout path: says so" has "is not a git checkout"
new_case; /usr/bin/trash "$C/agent.plist"; go
check "no plist: exit 1" [ "$RC" = 1 ]
new_case; ahead "two"; g "$C/proxy" commit -q --allow-empty -m local; g "$C/proxy" pull -q --no-rebase --no-edit origin main 2>/dev/null; go
check "ahead and merged: no notice" [ ! -f "$C/shown" ]
new_case; check "no host value in the job" bash -c "! grep -qF 'nelson''.love' '$here/../run.sh' '$here/../public-hostname.example' '$here/../../../jobs/vault-mcp-remote-update.yaml'"

# notice.sh itself
new_case; OUT=$(NOTICE_CMD="$C/notice-stub" NOTICE_STATE_DIR="$C/n" "$NOTICE" job-x "A title" $'line one\nline two' 2>&1); RC=$?
check "notice: exit 0" [ "$RC" = 0 ]; check "notice: first line shown" grep -qx 'A title|line one' "$C/shown"
check "notice: full text kept" grep -qx 'line two' "$C/n/job-x/latest-notice.md"
OUT=$(NOTICE_CMD="$C/notice-stub" NOTICE_STATE_DIR="$C/n" "$NOTICE" job-x "" "m" 2>&1); RC=$?; check "notice: empty title refused" [ "$RC" = 1 ]

printf '%d passed, %d failed\n' "$pass" "$fail"; [ "$fail" = 0 ] || { printf 'failed:%b\n' "$failed"; exit 1; }
