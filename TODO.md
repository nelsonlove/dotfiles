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
- [ ] Remove old ~/.config/secrets/ once iCloud secrets (06.04) is confirmed working

## Other TODOs

### Port yabai config to AeroSpace
- Source: `~/repos/dotfiles/inactive/yabai/.yabairc` + `inactive/skhd/skhdrc`
- Key features to port: BSP layout (no gaps), modal keybindings (hyper-w), float rules (System Settings, Finder, Karabiner), focus-follows-mouse
- Output: `~/.aerospace.toml` + stow-managed config in dotfiles repo
- Drop yabai/skhd taps (`koekeishiya/formulae`) after port confirmed working
