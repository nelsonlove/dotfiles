# Nix-Darwin + Home-Manager Setup

## Goal

Replace manual bootstrap script with a declarative Nix flake. A single
`darwin-rebuild switch` manages: dotfile symlinks, CLI packages, Homebrew
casks, macOS defaults, and a custom Emacs build from source.

## Approach

Raw flake — nix-darwin + home-manager as a module, no framework (no Snowfall
Lib, no flake-parts). Maximum transparency, minimum abstraction.

## Repo Structure

```
dotfiles/
├── flake.nix              # Entry point — pins inputs, composes system
├── flake.lock
├── hosts/
│   └── default.nix        # nix-darwin: Nix settings, Homebrew, macOS defaults
├── home/
│   └── default.nix        # home-manager: symlinks, user packages
├── overlays/
│   └── emacs-mac.nix      # Custom emacs-mac build (jdtsmith branch)
├── emacs/                 # Config files (unchanged, symlinked by home-manager)
├── alacritty/             # Config files (unchanged, symlinked by home-manager)
├── install/
│   └── manifest.yaml      # Legacy reference, superseded by flake
└── ...
```

## Flake Inputs

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  nix-darwin = {
    url = "github:nix-darwin/nix-darwin";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

All three inputs share the same nixpkgs. home-manager runs as a nix-darwin
module so `darwin-rebuild switch` handles everything in one pass.

## Dotfile Symlinks

Use `mkOutOfStoreSymlink` so symlinks point directly to the repo, not the Nix
store. Edits are live — no rebuild needed for config changes.

```nix
home.file.".config/emacs".source =
  config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/repos/dotfiles/emacs";
```

Produces: `~/.config/emacs → ~/repos/dotfiles/emacs`

## Emacs Build

Override `emacsMacport` from nixpkgs to pin the jdtsmith branch:

```nix
# overlays/emacs-mac.nix
final: prev: {
  emacs-mac-custom = prev.emacsMacport.overrideAttrs (old: {
    version = "30.1-jdtsmith";
    src = prev.fetchFromBitbucket { /* pin commit */ };
    configureFlags = (old.configureFlags or []) ++ [
      "--with-mac-metal"
      "--with-native-compilation"
    ];
  });
}
```

Replaces manual `./configure && make`. Nix handles dependencies and caching.

## Homebrew

nix-darwin manages Homebrew declaratively. `cleanup = "zap"` enforces the
declared list — anything not listed gets removed.

```nix
homebrew = {
  enable = true;
  onActivation = {
    autoUpdate = true;
    cleanup = "zap";
  };
  casks = [ "alacritty" "1password" "claude" /* ... */ ];
};
```

## macOS Defaults

Declared in Nix, applied on rebuild:

```nix
system.defaults = {
  dock.autohide = true;
  finder.AppleShowAllExtensions = true;
  NSGlobalDomain.AppleInterfaceStyle = "Dark";
};
```

## Bootstrap (Fresh Machine / VM)

```bash
# 1. Install Nix (Determinate Systems — flakes enabled out of the box)
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install

# 2. Clone dotfiles
git clone git@github.com:nelsonlove/dotfiles.git ~/repos/dotfiles

# 3. First build (darwin-rebuild doesn't exist yet)
cd ~/repos/dotfiles
nix run nix-darwin -- switch --flake .

# 4. Subsequent rebuilds
darwin-rebuild switch --flake .
```

## Migration Strategy

Start minimal, grow incrementally:

- **Day one**: emacs + alacritty symlinks, emacs-mac build, a few core CLI
  packages, a few casks
- **Over time**: add CLI packages (replacing Homebrew formulae), casks, macOS
  defaults, shell config (zsh/tmux)
- **Eventually**: manifest.yaml becomes redundant, flake is the single source
  of truth

## Testing

Build and test in a macOS VM before applying to the real machine.
