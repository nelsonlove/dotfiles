#!/bin/bash
# _lib/gated.sh <host> <job-id>
# Tickle gate: run the job only if BOTH _lib/on-host.sh <host> and
# _lib/pause-gate.sh <job-id> pass. Exits with the first non-zero code.
#
# Tickle registers every entry in `triggers:` independently, so two trigger
# entries are an OR, not an AND — either one firing runs the job (see
# internal/scheduler replaceSchedule/registerTrigger). A job that must satisfy
# two conditions therefore needs ONE trigger that calls this wrapper.
#
# Exit-code contract is the script-trigger one: 0 run, 1 skip, other failed.
# A bad argument list exits 2 so a mis-wired trigger is loud, not a silent skip.
#
# Usage in a job YAML:
#   triggers:
#     - type: script
#       schedule: "*/30 * * * *"
#       command: ["@config/scripts/_lib/gated.sh", "<host>", "<job-id>"]
#       timeout: 10s
set -u

if [ "$#" -ne 2 ]; then
  echo "usage: gated.sh <host> <job-id>" >&2
  exit 2
fi

lib_dir=$(cd "$(dirname "$0")" && pwd)

"$lib_dir/on-host.sh" "$1" || exit $?
exec "$lib_dir/pause-gate.sh" "$2"
