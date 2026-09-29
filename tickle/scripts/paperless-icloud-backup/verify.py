#!/usr/bin/env python3
"""Check a local copy of a Paperless-ngx export against its manifest.

Fails (exit 1) when:
  - manifest.json is missing, unreadable, or lists no documents;
  - any document's original file named in the manifest is missing;
  - any original's MD5 does not match the manifest's `checksum`;
  - any archive file named in the manifest is missing, or its MD5 does not
    match `archive_checksum`;
  - the document count fell by more than MAX_DROP since the last good run.

Paperless-ngx 2.x writes one manifest.json: a list of objects with `model`,
`fields`, and `__exported_file_name__` / `__exported_archive_name__` for
documents. The checksums are MD5 of the file bytes.

State (the last good count) lives beside the export, in `.verify-state.json`.
"""
import hashlib
import json
import sys
from pathlib import Path

MAX_DROP = 5


def md5(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify.py <export-dir>", file=sys.stderr)
        return 2
    root = Path(sys.argv[1])
    manifest_path = root / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, ValueError) as e:
        print(f"FATAL: cannot read {manifest_path}: {e}", file=sys.stderr)
        return 1

    docs = [r for r in manifest if r.get("model") == "documents.document"]
    if not docs:
        print(f"FATAL: {manifest_path} lists no documents.", file=sys.stderr)
        return 1

    problems = []
    for r in docs:
        f = r.get("fields", {})
        pk = r.get("pk")
        pairs = [("__exported_file_name__", "checksum")]
        if r.get("__exported_archive_name__"):
            pairs.append(("__exported_archive_name__", "archive_checksum"))
        for name_key, sum_key in pairs:
            name = r.get(name_key)
            if not name:
                problems.append(f"document {pk}: manifest has no {name_key}")
                continue
            p = root / name
            if not p.is_file():
                problems.append(f"document {pk}: missing {name}")
            elif f.get(sum_key) and md5(p) != f[sum_key]:
                problems.append(f"document {pk}: checksum mismatch for {name}")

    state_path = root.parent / ".verify-state.json"
    last = None
    try:
        last = json.loads(state_path.read_text()).get("documents")
    except (OSError, ValueError):
        pass
    if isinstance(last, int) and len(docs) < last - MAX_DROP:
        problems.append(f"document count fell from {last} to {len(docs)} (more than {MAX_DROP})")

    if problems:
        print(f"FATAL: {len(problems)} problem(s) in {root}:", file=sys.stderr)
        for line in problems[:50]:
            print(f"  {line}", file=sys.stderr)
        return 1

    state_path.write_text(json.dumps({"documents": len(docs)}) + "\n")
    print(f"ok: {len(docs)} documents, every file present and matching its checksum (local copy; iCloud upload not checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
