#!/bin/sh
# Tickle gate: exit 0 if this machine is the host named in $1, else exit 1.
# Used as a `type: script` trigger so a job runs on only one host.
#
# Checks scutil's LocalHostName FIRST, and the kernel short hostname only as an
# alternate. The kernel name follows the network and is not a stable identity:
# DHCP can push one, and macOS auto-renames on a Bonjour collision. On
# 2026-09-14 the Air's `hostname -s` became `Mac` while LocalHostName stayed
# `Nelsons-MacBook-Air` — this gate then failed closed and `obsidian-backup`
# silently skipped every run for about 29 hours, with no error anywhere,
# because a skipped trigger is indistinguishable from a healthy quiet period.
# LocalHostName is user-set in Sharing preferences and is far steadier — but it
# is NOT immune: it is also the Bonjour .local name, so mDNSResponder can suffix
# it (Nelsons-MacBook-Air-2) when that name collides on the LAN. If that happens
# both names drift at once and this gate fails closed again. That is the
# residual failure this script cannot fix, and the reason nothing here should be
# the only thing watching whether a scheduled job is still running.
#
# Matching EITHER name is deliberate: any host that passes today keeps passing,
# so this cannot break a job on a machine whose two names already agree. An
# empty name never matches, so an absent scutil or an empty $1 fails closed.
for _n in "$(scutil --get LocalHostName 2>/dev/null)" "$(hostname -s 2>/dev/null)"; do
  [ -n "$_n" ] && [ "$_n" = "$1" ] && exit 0
done
exit 1
