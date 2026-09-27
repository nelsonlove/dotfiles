#!/usr/bin/env python3
"""[test artifact — safe to delete] run the inversion battery. No shell touches a payload's bytes."""
import json, pathlib, subprocess, sys

guard = sys.argv[1]
d = pathlib.Path("/tmp/v3/cases")
manifest = json.loads((d / "manifest.json").read_text())
fails = 0
for row in manifest:
    payload = (d / row["file"]).read_bytes()
    r = subprocess.run([guard], input=payload, capture_output=True)
    ok = r.returncode == row["want"]
    if not ok:
        fails += 1
        first = (r.stderr.decode(errors="replace").splitlines() or [""])[0]
        print(f'FAIL  {row["label"]:<62} rc={r.returncode} (wanted {row["want"]})\n      {first[:150]}')
    elif "-v" in sys.argv:
        print(f'PASS  {row["label"]:<62} rc={r.returncode}')
print(f'\n{len(manifest)} cases, {fails} failed')
sys.exit(1 if fails else 0)
