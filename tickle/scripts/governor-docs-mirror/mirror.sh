#!/bin/bash
# governor-docs-mirror — one-way mirror of the obsidian-governor repo's committed docs into the vault.
# Canonical is the repo (origin/main). The mirror is generated and disposable: every run rebuilds
# the tree and rsyncs it over the vault copy, so hand edits and vault-side rewrites are overwritten.
# Frontmatter injected per file keeps the automatic-linker and Linter off the mirror.
set -euo pipefail

REPO="/Users/nelson/repos/system/obsidian-governor"
DEST="/Users/nelson/obsidian/00-09 System/00 System management/00.89 obsidian-governor/Docs (repo mirror)"
REF="origin/main"

# Freshen the ref; tolerate being offline (mirror then reflects the last fetched state).
git -C "$REPO" fetch --quiet origin main 2>/dev/null || true

SHA=$(git -C "$REPO" rev-parse --short "$REF")
STAMP=$(date '+%Y-%m-%d %H:%M')

TMP=$(mktemp -d "${TMPDIR:-/tmp}/governor-docs-mirror.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

git -C "$REPO" ls-tree -r --name-only "$REF" \
    | grep -E '^(README|CONTRIBUTING|PRIVACY|SECURITY|SUPPORT)\.md$|^docs/.*\.md$|^submission/.*\.md$' \
    | while IFS= read -r rel; do
        out="$TMP/$rel"
        mkdir -p "$(dirname "$out")"
        {
            printf -- '---\n'
            printf 'mirror-of: "nelsonlove/obsidian-governor %s @ %s"\n' "$rel" "$SHA"
            printf 'mirror-refreshed: %s\n' "$STAMP"
            printf 'automatic-linker-disabled: true\n'
            printf 'disabled rules: [all]\n'
            printf -- '---\n'
            if [ "$rel" = "README.md" ]; then
                printf '\n> [!info] Generated mirror of the canonical repo docs (`%s` @ `%s`). Edits here are overwritten on refresh.\n' "$REF" "$SHA"
            fi
            printf '\n'
            git -C "$REPO" show "$REF:$rel"
        } > "$out"
    done

mkdir -p "$DEST"
# Skip the rsync entirely when the source sha is unchanged — otherwise the per-run
# mirror-refreshed stamp would churn every file (and Obsidian Sync) on every interval.
LAST_SHA_FILE="$DEST/.mirror-sha"
if [ -f "$LAST_SHA_FILE" ] && [ "$(cat "$LAST_SHA_FILE")" = "$SHA" ]; then
    echo "mirror current at $SHA; nothing to do"
    exit 0
fi

rsync -a --checksum --delete --exclude '.mirror-sha' "$TMP/" "$DEST/"
printf '%s' "$SHA" > "$LAST_SHA_FILE"
echo "mirrored $(find "$TMP" -name '*.md' | wc -l | tr -d ' ') files at $SHA"
