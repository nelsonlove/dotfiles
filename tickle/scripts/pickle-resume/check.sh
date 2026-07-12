#!/bin/sh
# MBP-only gate for cold-resume, then delegate to has-answers.sh — whose JSON
# stdout + exit code drive the actual resume decision (shared vault inbox but
# per-machine claims → single resumer avoids ops_handoff double-runs).
"$(dirname "$0")/../_lib/on-host.sh" "Nelsons-MacBook-Pro" || exit 1
exec "$(dirname "$0")/has-answers.sh"
