#!/usr/bin/env bash
# Audit installed apps by how they're managed, to surface reproducibility gaps.
#
#   App Store  -> has Contents/_MASReceipt/ in the bundle
#   Homebrew   -> app name matches a cask declared in install/Brewfile
#   UNMANAGED  -> neither (manual drag-install / direct download / licensed installer)
#
# Usage:  install/audit-unmanaged-apps.sh                # list unmanaged apps
#         install/audit-unmanaged-apps.sh --suggest-casks # also note which have a cask
#
# Note: classifies against what the Brewfile *declares* as casks, not what brew
# currently has installed — so an app you hand-installed but later added to the
# Brewfile counts as managed. Run after `brew update` for fresh cask metadata.

set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SUGGEST=0; [[ "${1:-}" == "--suggest-casks" ]] && SUGGEST=1

BREWFILE="$SCRIPT_DIR/Brewfile" SUGGEST="$SUGGEST" python3 - <<'PY'
import subprocess, json, os, glob, re
def sh(c): return subprocess.run(c, shell=True, capture_output=True, text=True).stdout
BF=os.environ["BREWFILE"]; SUGGEST=os.environ["SUGGEST"]=="1"

# cask tokens declared in the Brewfile (strip tap-path prefixes like a/b/c)
tokens=[t.split('/')[-1] for t in re.findall(r'^cask "([^"]+)"', open(BF).read(), re.M)]
declared=set()
if tokens:
    data=json.loads(sh("brew info --cask --json=v2 "+" ".join(tokens)+" 2>/dev/null") or '{"casks":[]}')
    for c in data.get("casks",[]):
        for art in c.get("artifacts",[]):
            if isinstance(art,dict):
                for a in art.get("app",[]) or []:
                    declared.add(a if isinstance(a,str) else (a.get("target") or a.get("source")))

# pkg-based casks (Karabiner-Elements, Tailscale, …) have no drag `.app`
# artifact, so match the app name against the cask token too as a fallback.
def norm(s): return re.sub(r'[^a-z0-9]+', '-', s.lower().replace('.app','')).strip('-')
token_norms = {norm(t) for t in tokens} | {norm(re.sub(r'-app$','',t)) for t in tokens}

HELP=re.compile(r'(Utility|Manager|Tray|URL Handler|Config$|EventViewer|Activation|Service|Remove |Control Center|Helper|Updater|Uninstall)', re.I)
APPLE={"Safari.app"}
apps=set()
for d in ["/Applications", os.path.expanduser("~/Applications")]:
    apps |= {os.path.basename(x) for x in glob.glob(d+"/*.app")}

mas=cask=0; gaps=[]
for n in sorted(apps):
    p=os.path.join("/Applications",n)
    if not os.path.exists(p): p=os.path.expanduser("~/Applications/"+n)
    if os.path.isdir(os.path.join(p,"Contents","_MASReceipt")): mas+=1; continue
    if n in declared or norm(n) in token_norms: cask+=1; continue
    if n in APPLE or HELP.search(n): continue
    gaps.append(n)

print(f"App Store: {mas} | declared cask (Brewfile): {cask} | unmanaged: {len(gaps)}\n")
print("UNMANAGED (not App Store, not in Brewfile):")
for n in gaps:
    note=""
    if SUGGEST:
        # quick fuzzy check: does a cask plausibly exist for this app?
        base=re.sub(r'\.app$','',n)
        hits=sh(f'brew search --cask "{base}" 2>/dev/null').strip().splitlines()
        hits=[h for h in hits if h and not h.startswith("==>")]
        if hits: note=f"   (cask? {', '.join(hits[:3])})"
    print(f"  {n.replace('.app','')}{note}")
PY
