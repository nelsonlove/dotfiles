#!/usr/bin/env bash
# Tests for the token guard in githooks/: the pre-commit hook, the CI range check, and the two warning hooks.
#
# EVERYTHING RUNS IN A THROWAWAY GIT REPO under the temp dir, never in the dotfiles repo: the hooks are copied
# in and wired with `core.hooksPath`, and each case makes real commits there.
#
# NO REAL-LOOKING TOKEN IS WRITTEN IN THIS FILE. The fakes are built from parts at run time, so this file never
# matches the patterns it tests (and the guard does not refuse its own test). A fake is the prefix plus a run
# of one repeated letter: the right shape, and plainly not a credential.
#
# Run: bash githooks/test-token-guard.sh   (prints the check count; exits non-zero on any failure)
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
n=0; fails=0
pass() { n=$((n + 1)); printf 'PASS  %s\n' "$1"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
# expect <label> <want-rc: 0|nonzero> <want-substring or ""> <command…>
expect() {
  local label="$1" want="$2" sub="$3"; shift 3
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [ "$want" = 0 ] && [ "$rc" -ne 0 ]; then fail "$label" "exit $rc, want 0: $(printf '%s' "$out" | head -3)"; return; fi
  if [ "$want" != 0 ] && [ "$rc" -eq 0 ]; then fail "$label" "exit 0, want a refusal"; return; fi
  if [ -n "$sub" ]; then
    case "$out" in *"$sub"*) ;; *) fail "$label" "output lacks \"$sub\": $(printf '%s' "$out" | head -3)"; return ;; esac
  fi
  pass "$label"
}

rep() { local s="" _; for _ in $(seq 1 "$2"); do s="$s$1"; done; printf '%s' "$s"; }
FAKE_CLASSIC="gh""p_$(rep A 36)"
FAKE_FINE="github""_pat_$(rep B 22)"
FAKE_OAUTH="gh""o_$(rep C 36)"

T=$(mktemp -d "${TMPDIR:-/tmp}/token-guard-test.XXXXXX") || exit 1
trap '/usr/bin/trash "$T" 2>/dev/null || true' EXIT
SECRET="$T/secret-target.json"; printf '{}\n' > "$SECRET"
# Files are moved aside into the temp dir, never deleted with rm (CLAUDE.md), and the temp dir goes to the
# trash at exit where there is one (on a CI runner there is none, and the runner is thrown away).
gone() { mv -- "$1" "$T/gone.$(date +%s).$RANDOM"; }

newrepo() {  # newrepo <dir>: a repo with the hooks copied in and wired, and one first commit
  local r="$1"
  mkdir -p "$r" && git -C "$r" init -q -b main
  git -C "$r" config user.email t@example.invalid; git -C "$r" config user.name test
  git -C "$r" config commit.gpgsign false
  mkdir -p "$r/githooks" "$r/claude"
  if [ -d "$HERE" ] && ls "$HERE"/pre-commit >/dev/null 2>&1; then
    cp "$HERE"/pre-commit "$HERE"/post-merge "$HERE"/post-checkout "$HERE"/token-guard.sh "$r/githooks/" 2>/dev/null
  fi
  git -C "$r" config core.hooksPath githooks
  ln -s "$SECRET" "$r/claude/settings.local.json"
  printf 'hello\n' > "$r/README"
  git -C "$r" add README claude/settings.local.json githooks >/dev/null 2>&1
  git -C "$r" commit -q -m first --no-verify
}

echo "=== pre-commit"
R="$T/r1"; newrepo "$R"
printf 'more\n' >> "$R/README"; git -C "$R" add README
expect "a clean commit passes" 0 "" git -C "$R" commit -q -m clean

# the settings file replaced by a regular file, and staged
gone "$R/claude/settings.local.json"; printf '{"token": "x"}\n' > "$R/claude/settings.local.json"
git -C "$R" add claude/settings.local.json
expect "a regular file at claude/settings.local.json is refused" 1 "claude/settings.local.json" git -C "$R" commit -q -m bad
expect "the refusal says why" 1 "not a symlink" git -C "$R" commit -q -m bad
git -C "$R" reset -q; gone "$R/claude/settings.local.json"; ln -s "$SECRET" "$R/claude/settings.local.json"

printf 'token=%s\n' "$FAKE_CLASSIC" > "$R/config.env"; git -C "$R" add config.env
expect "a staged classic token is refused, and the path named" 1 "config.env" git -C "$R" commit -q -m bad
git -C "$R" reset -q; gone "$R/config.env"

printf 'token=%s\n' "$FAKE_FINE" > "$R/other.txt"; git -C "$R" add other.txt
expect "a staged fine-grained token is refused" 1 "other.txt" git -C "$R" commit -q -m bad
git -C "$R" reset -q; gone "$R/other.txt"

printf 'token=%s\n' "$FAKE_OAUTH" > "$R/oauth.txt"; git -C "$R" add oauth.txt
expect "a staged OAuth (gho_) token is refused" 1 "oauth.txt" git -C "$R" commit -q -m bad
git -C "$R" reset -q; gone "$R/oauth.txt"

mkdir -p "$R/sub dir"; printf '%s\n' "$FAKE_CLASSIC" > "$R/sub dir/a file.txt"; git -C "$R" add "sub dir"
expect "a path with spaces is scanned and named" 1 "sub dir/a file.txt" git -C "$R" commit -q -m bad
git -C "$R" reset -q; gone "$R/sub dir"

printf 'ghp_short\n' > "$R/near.txt"; git -C "$R" add near.txt
expect "a near miss (too short) passes" 0 "" git -C "$R" commit -q -m near

echo
echo "=== the CI range check (token-guard.sh --range BASE HEAD)"
R="$T/r2"; newrepo "$R"
base=$(git -C "$R" rev-parse HEAD)
printf '%s\n' "$FAKE_CLASSIC" > "$R/leak.txt"; git -C "$R" add leak.txt; git -C "$R" commit -q -m add --no-verify
git -C "$R" rm -q leak.txt; git -C "$R" commit -q -m remove --no-verify
expect "a token added then removed inside the range is refused" 1 "leak.txt" bash "$R/githooks/token-guard.sh" --range "$base" HEAD --repo "$R"
# Review 1 of #74: three ways the history scan lost a token.
R="$T/r2b"; newrepo "$R"; base=$(git -C "$R" rev-parse HEAD)
printf '%s\n' "$FAKE_CLASSIC" > "$R/caf$(printf '\303\251').txt"; git -C "$R" add .; git -C "$R" commit -q -m add --no-verify
git -C "$R" rm -q "caf$(printf '\303\251').txt"; git -C "$R" commit -q -m remove --no-verify
expect "a token in a file with a non-ASCII name, added then removed, is refused" 1 "caf" bash "$R/githooks/token-guard.sh" --range "$base" HEAD --repo "$R"
R="$T/r2c"; newrepo "$R"; base=$(git -C "$R" rev-parse HEAD)
printf '++ x\n%s\n' "$FAKE_CLASSIC" > "$R/plus.txt"; git -C "$R" add plus.txt; git -C "$R" commit -q -m add --no-verify
git -C "$R" rm -q plus.txt; git -C "$R" commit -q -m remove --no-verify
expect "a token after a line that starts with ++ is refused" 1 "plus.txt" bash "$R/githooks/token-guard.sh" --range "$base" HEAD --repo "$R"
R="$T/r2d"; newrepo "$R"; base=$(git -C "$R" rev-parse HEAD)
git -C "$R" checkout -q -b side; printf 'side\n' > "$R/side.txt"; git -C "$R" add side.txt; git -C "$R" commit -q -m side --no-verify
git -C "$R" checkout -q main; printf 'main\n' > "$R/main.txt"; git -C "$R" add main.txt; git -C "$R" commit -q -m main --no-verify
git -C "$R" merge -q --no-commit --no-ff side >/dev/null 2>&1; printf '%s\n' "$FAKE_CLASSIC" > "$R/merged.txt"; git -C "$R" add merged.txt
git -C "$R" commit -q -m merge --no-verify; git -C "$R" rm -q merged.txt; git -C "$R" commit -q -m remove --no-verify
expect "a token added in a merge commit, removed after, is refused" 1 "merged.txt" bash "$R/githooks/token-guard.sh" --range "$base" HEAD --repo "$R"
# Review 2 of #74: --history scans every commit of the head (the CI fallback when a push's base is unknown),
# and a diff.noprefix config does not hide the file name.
R="$T/r2e"; newrepo "$R"
printf '%s\n' "$FAKE_CLASSIC" > "$R/early.txt"; git -C "$R" add early.txt; git -C "$R" commit -q -m a --no-verify
git -C "$R" rm -q early.txt; git -C "$R" commit -q -m b --no-verify
printf 'c\n' >> "$R/README"; git -C "$R" add README; git -C "$R" commit -q -m c --no-verify
expect "--history finds a token added and removed anywhere before the head" 1 "early.txt" bash "$R/githooks/token-guard.sh" --history HEAD --repo "$R"
git -C "$R" config diff.noprefix true
expect "diff.noprefix does not hide the file name" 1 "early.txt" bash "$R/githooks/token-guard.sh" --range "$(git -C "$R" rev-list --max-parents=0 HEAD)" HEAD --repo "$R"
R="$T/r3"; newrepo "$R"
base=$(git -C "$R" rev-parse HEAD)
gone "$R/claude/settings.local.json"; printf '{}\n' > "$R/claude/settings.local.json"
git -C "$R" add claude/settings.local.json; git -C "$R" commit -q -m reg --no-verify
expect "a regular settings file at HEAD is refused" 1 "claude/settings.local.json" bash "$R/githooks/token-guard.sh" --range "$base" HEAD --repo "$R"
R="$T/r4"; newrepo "$R"
base=$(git -C "$R" rev-parse HEAD)
printf 'fine\n' >> "$R/README"; git -C "$R" add README; git -C "$R" commit -q -m ok --no-verify
expect "a clean range passes" 0 "" bash "$R/githooks/token-guard.sh" --range "$base" HEAD --repo "$R"
expect "an empty base is bad usage, not a pass" 1 "non-empty" bash "$R/githooks/token-guard.sh" --range "" HEAD --repo "$R"

echo
echo "=== post-merge and post-checkout warn, and never fail"
R="$T/r5"; newrepo "$R"
gone "$R/claude/settings.local.json"; printf '{}\n' > "$R/claude/settings.local.json"
expect "post-merge warns on a regular file" 0 "not a symlink" bash -c "cd '$R' && sh githooks/post-merge 0"
expect "post-checkout warns on a regular file" 0 "not a symlink" bash -c "cd '$R' && sh githooks/post-checkout a b 1"
expect "the warning names the fix" 0 "09.11" bash -c "cd '$R' && sh githooks/post-merge 0"
gone "$R/claude/settings.local.json"; ln -s "$SECRET" "$R/claude/settings.local.json"
out=$(cd "$R" && sh githooks/post-merge 0 2>&1); if [ -z "$out" ]; then pass "post-merge is silent on the symlink"; else fail "post-merge is silent on the symlink" "$out"; fi
out=$(cd "$R" && sh githooks/post-checkout a b 1 2>&1); if [ -z "$out" ]; then pass "post-checkout is silent on the symlink"; else fail "post-checkout is silent on the symlink" "$out"; fi

echo
echo "=== this file does not match the patterns it tests"
if grep -qE 'gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}' "$0"; then fail "no real-looking token in the test file"; else pass "no real-looking token in the test file"; fi

EXPECTED=23
printf '\n%s checks (expected %s), %s failed\n' "$n" "$EXPECTED" "$fails"
[ "$n" = "$EXPECTED" ] || { echo "FAIL  the check count is $n, expected $EXPECTED"; exit 1; }
[ "$fails" = 0 ] || exit 1
