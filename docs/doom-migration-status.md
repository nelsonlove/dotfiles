# Doom Config Migration Status

**Date:** 2026-03-04

## Where things live

- **Doom config archive:** `06.01 Digital tools - Unsorted/doom/`
- **Standalone Emacs config:** `~/repos/dotfiles/emacs/`
- **Staged ports (not wired in yet):** `~/repos/dotfiles/emacs/lisp/`

## Ported to emacs/lisp/ (ready to require)

| File | Origin | Contents |
|------|--------|----------|
| `my-editor.el` | `config/editor/config.el` | `my/duplicate-line` (s-d), `my/fill-or-unfill-paragraph`, `my/arrayify` |
| `my-buffers.el` | `config/emacs/config.el` | `my/buffer-old-p`, `my/buffer-dissociated-p`, `my/ibuffer-mark-stale-buffers` |
| `my-lookup.el` | `config/tools/lookup.el` | `my/ascii-lookup`, `my/key-lookup` (search all keymaps for a key sequence) |
| `my-macos.el` | `config/os/macos.el` | Smooth scroll, native fullscreen toggle, `my/open-in-alacritty` |
| `my-autotheme.el` | `modules/ui/autotheme/` | Solar + macOS appearance-based light/dark theme switching with timers/hooks |
| `my-org.el` | `config/lang/org/config.el` | GTD: TODO keywords/faces, capture templates, refile, agenda, crypt, archive, babel defaults, structure templates, hourly auto-save |

All Doom dependencies removed: `after!` → `with-eval-after-load`, `map!` → `keymap-global-set`/`define-key`, no `doom-path`, no `modulep!`, no `+workspace`.

To activate, add to `config.el`:
```elisp
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(require 'my-editor)
(require 'my-buffers)
(require 'my-lookup)
(require 'my-macos)
(require 'my-autotheme)
(require 'my-org)
```

## Not yet ported

### Needs packages first
- **org-roam** (`config/lang/org/+roam2.el`) — capture templates, node display, export-to-md, alias/tag/ref keybinds. Needs `org-roam` package.
- **org-journal** (`config/lang/org/+journal.el`) — capture templates, workspace integration. Needs `org-journal` package.
- **GPT module** (`modules/tools/gpt/`) — OpenAI integration with context-aware prompts, magit commit generation, docstring generation, caching, transient menus. Needs `request` package + API key.
- **Stack Overflow** (`config/tools/lookup.el`) — sx.el keybindings. Needs `sx` package.

### Needs architecture decisions
- **Workspaces** (`config/ui/workspaces.el`) — Doom's `+workspace` API. Would need `tab-bar-mode` or `perspective.el` as replacement.
- **Modeline** (`config/ui/modeline.el`) — Custom doom-modeline segments. Would need doom-modeline or alternative.

### Skip (work-specific or obsolete)
- **ESP module** (`modules/tools/esp/`) — old L7 work project tooling
- **Slack** (`config/app/slack.el`) — needs workspace tokens
- **Copilot** (`config/completion/copilot.el`) — replaced by other AI tools
- **Modular config loader** (`modules/config/modular/`) — Doom module system dependency

## Also in the doom archive

- `etc/` — reference library (Sacha Chua's config, Bernt Hansen's GTD org setup, refcards, old literate config experiments, chemacs, emagicians-starter-kit)
- `org-git-sync.sh` — auto-commit/push org files (useful standalone script)
- `autoload/org.el` — `+org-entry-is-project-p` (checks if heading has TODO subtasks)
- `snippets/` — work-specific yasnippet, skip

## Changes also made to standalone config this session

- Added `xterm-mouse-mode` for terminal Emacs (mouse works in tmux now)
- Reverted obsidian.el to load unconditionally (vault scan is slow in `-nw` but daemon handles it)
