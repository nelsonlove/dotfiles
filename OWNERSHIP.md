# Ownership

This repository is split between two ships of Nelson's fleet of Claude Code sessions. Nelson ruled it on 2026-09-29: "A, MA".

`claude/` belongs to the claude code ship, whose captain is `[C0-CC] claude code`. It holds the Claude Code configuration, hooks, scripts and their tests.

Everything else belongs to the macOS ship, whose captain is `[C0-MA] macos`. That is the shell, Homebrew, LaunchAgents, the tickle jobs, the install system and every other file outside `claude/`.

A pull request that touches both sides needs a review from both captains before it merges.

This is `OWNERSHIP.md` and not `CODEOWNERS` because both captains push as the same GitHub user, so `CODEOWNERS` cannot tell them apart.
