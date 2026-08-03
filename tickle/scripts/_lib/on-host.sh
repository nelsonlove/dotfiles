#!/bin/sh
# Tickle gate: exit 0 if this machine's stable local hostname == $1, else 1.
# Used as a `type: script` trigger so a job runs on only one host.
# Prefers scutil's LocalHostName, which stays stable when DHCP pushes a
# hostname or macOS auto-renames on a name collision (both shift `hostname -s`
# and would silently stop the job). Falls back to hostname -s off macOS.
[ "$(scutil --get LocalHostName 2>/dev/null || hostname -s)" = "$1" ]
