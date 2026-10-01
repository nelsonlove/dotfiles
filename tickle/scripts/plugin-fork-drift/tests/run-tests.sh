#!/bin/bash
# Tests for plugin-fork-drift/run.sh with the plain notice. Throwaway repos under /tmp; the notice goes to a stub (NOTICE_CMD).
set -u
here=$(cd "$(dirname "$0")" && pwd -P); RUN="$here/../run.sh"
pass=0; fail=0; failed=""
ROOT=$(mktemp -d /tmp/pfd-tests.XXXXXX); trap '/usr/bin/trash "$ROOT" 2>/dev/null' EXIT
check() { n="$1"; shift; if "$@"; then pass=$((pass+1)); else fail=$((fail+1)); failed="$failed\n  - $n"; printf 'FAIL %s\n---\n%s\n---\n' "$n" "$OUT"; fi; }
g() { git -C "$1" -c user.name=t -c user.email=t@example.invalid "${@:2}"; }
new_case() {
  C=$(mktemp -d "$ROOT/case.XXXXXX"); mkdir -p "$C/plugins" "$C/repos"
  git init -q --bare "$C/up.git"; git init -q -b main "$C/seed"; g "$C/seed" commit -q --allow-empty -m one
  g "$C/seed" remote add origin "$C/up.git"; g "$C/seed" push -q origin main; git -C "$C/up.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$C/up.git" "$C/repos/fork-a"; git -C "$C/repos/fork-a" remote add fork "$C/up.git"; git -C "$C/repos/fork-a" checkout -q -b nl-main
  printf '#!/bin/bash\nprintf "%%s\\n" "$1" >> "%s/shown"\nexit "$(cat "%s/notice_rc" 2>/dev/null || echo 0)"\n' "$C" "$C" > "$C/stub"; chmod +x "$C/stub"
}
go() { OUT=$(env -i HOME="$C" PATH=/usr/bin:/bin REPO_ROOT="$C/repos" VAULT_PLUGINS="$C/plugins" STATE_DIR="$C/state" NOTICE_CMD="$C/stub" NOTICE_STATE_DIR="$C/n" /bin/bash "$RUN" 2>&1); RC=$?; }

new_case; go; check "clean: exit 0" [ "$RC" = 0 ]; check "clean: no notice" [ ! -f "$C/shown" ]
new_case; g "$C/seed" commit -q --allow-empty -m "upstream fix"; g "$C/seed" push -q origin main; go
check "behind: exit 0" [ "$RC" = 0 ]; check "behind: notice" grep -qF 'plugin forks: 1 need attention' "$C/shown"
check "behind: full text kept" grep -qF 'fork-a (ahead 0): 1 behind' "$C/n/plugin-fork-drift/latest-notice.md"
check "behind: state recorded" [ -s "$C/state/fork-a.rev" ]
go; check "same rev: no second notice" [ "$(wc -l < "$C/shown" | tr -d ' ')" = 1 ]
new_case; g "$C/seed" commit -q --allow-empty -m x; g "$C/seed" push -q origin main; echo 1 > "$C/notice_rc"; go
check "notice fails: exit 1" [ "$RC" = 1 ]; check "notice fails: no state" [ ! -f "$C/state/fork-a.rev" ]
new_case; /usr/bin/trash "$C/plugins"; go; check "not the plugin host: exit 0 quietly" [ "$RC" = 0 ]
check "no Pickle call left" bash -c "! grep -vE '^[[:space:]]*#' '$RUN' | grep -qiE 'comms-send|pickle'"

printf '%d passed, %d failed\n' "$pass" "$fail"; [ "$fail" = 0 ] || { printf 'failed:%b\n' "$failed"; exit 1; }
