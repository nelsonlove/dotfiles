#!/bin/zsh
# Tickle job: nudge the vault-skills Obsidian exporter to regenerate the
# generated Claude Code plugin at ~/.claude/plugins/cache/.../vault-skills.
#
# WHY THIS EXISTS: the vault notes sync across machines (Obsidian Sync), but the
# GENERATED plugin lives in ~/.claude (gitignored, per-machine). So every machine
# must run its own export to pick up note edits made anywhere. export-on-save
# covers the machine actively editing; this is the hourly freshness backstop.
# Runs on BOTH machines by design — do not host-gate it.
#
# No-ops when Obsidian isn't running (export-on-save handles live editing; a
# closed Obsidian has nothing to export). Fires the plugin's own command via
# Advanced URI so the exporter runs inside Obsidian with its configured settings.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

if ! pgrep -xq Obsidian; then
  echo "skip: Obsidian not running"
  exit 0
fi

open -g 'obsidian://advanced-uri?vault=obsidian&commandid=vault-skills%3Aexport'
echo "triggered vault-skills:export at $(date +%H:%M)"
