#!/bin/sh
# Tickle gate: exit 0 if this machine's short hostname == $1, else exit 1.
# Used as a `type: script` trigger so a job runs on only one host.
[ "$(hostname -s)" = "$1" ]
