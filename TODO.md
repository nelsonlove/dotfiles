# TODO

## Config management
- [ ] Claude Code: decide on canonical config location (~/.claude vs ~/.config/claude)
- [ ] Claude Code: split settings.json into versionable prefs vs machine-specific

## Pending migrations
- [ ] Remaining macos-migration.nix items: duti, chflags, nvram, Transmission, Messages smart quotes

## VM testing
- [ ] Uncomment dock persistent-apps once homebrew apps are installed
- [ ] Verify .ssh permissions through iCloud symlink

## Cleanup
- [x] Remove old ~/.config/secrets/ once iCloud secrets is confirmed working (gone as of 2026-07-11; slot is now 09.11 after renumbers)
- [ ] `bvanrijn/wrangler` tap: untap or declare in Brewfile
- [ ] `pickle-ios` (~/repos) has no git remote — push it somewhere
- [ ] Duplicate clones in ~/repos AND ~/src: claude-code-plugins, ops — pick one home each
- [ ] Brewfile `npm "obsidian-mcp-server"` is third-party (cyanheads), not installed on MBA — keep or drop?

## Other TODOs

### Port yabai config to AeroSpace
- Source: `~/repos/dotfiles/inactive/yabai/.yabairc` + `inactive/skhd/skhdrc`
- Key features to port: BSP layout (no gaps), modal keybindings (hyper-w), float rules (System Settings, Finder, Karabiner), focus-follows-mouse
- Output: `~/.aerospace.toml` + stow-managed config in dotfiles repo
- Drop yabai/skhd taps (`koekeishiya/formulae`) after port confirmed working
