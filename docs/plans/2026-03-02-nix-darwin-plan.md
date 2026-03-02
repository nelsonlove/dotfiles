# Nix-Darwin + Home-Manager Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Declarative macOS system management via nix-darwin + home-manager flake, starting with dotfile symlinks, custom emacs-mac build, and a few core packages.

**Architecture:** Raw Nix flake (no framework). nix-darwin for system-level config (Homebrew, macOS defaults). home-manager as a nix-darwin module for user-level config (symlinks, packages). Per-host config files with a shared module.

**Tech Stack:** Nix flakes, nix-darwin, home-manager, Determinate Systems installer

---

### Task 1: Install Nix

**Step 1: Install Nix via Determinate Systems installer**

Run:
```bash
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install
```

Restart shell after install.

**Step 2: Verify Nix works**

Run: `nix --version`
Expected: version string (e.g. `nix (Nix) 2.x.x`)

Run: `nix flake --help`
Expected: help text (flakes enabled out of the box)

**Step 3: Commit** — nothing to commit, no repo changes.

---

### Task 2: Create flake.nix

**Files:**
- Create: `flake.nix`

**Step 1: Write flake.nix**

```nix
{
  description = "Nelson's macOS system configuration";

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

  outputs = { self, nixpkgs, nix-darwin, home-manager, ... }:
    let
      mkDarwinHost = { system, hostname }:
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit hostname; };
          modules = [
            ./hosts/shared.nix
            ./hosts/${hostname}.nix

            { nixpkgs.overlays = [ (import ./overlays/emacs-mac.nix) ]; }

            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.nelson = import ./home/default.nix;
            }
          ];
        };
    in
    {
      darwinConfigurations = {
        Nelsons-MacBook-Pro = mkDarwinHost {
          system = "aarch64-darwin";
          hostname = "Nelsons-MacBook-Pro";
        };
        # Add more machines:
        # WorkMac = mkDarwinHost {
        #   system = "aarch64-darwin";
        #   hostname = "WorkMac";
        # };
      };
    };
}
```

**Step 2: Generate lock file**

Run: `cd ~/repos/dotfiles && nix flake lock`
Expected: `flake.lock` created with pinned revisions.

**Step 3: Commit**

```bash
git add flake.nix flake.lock
git commit -m "Add flake.nix with nix-darwin + home-manager inputs"
```

---

### Task 3: Create shared host config

**Files:**
- Create: `hosts/shared.nix`

**Step 1: Write hosts/shared.nix**

This is the config that applies to every machine.

```nix
{ pkgs, hostname, ... }:

{
  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "nelson" ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # System packages (available to all users)
  environment.systemPackages = with pkgs; [
    git
    ripgrep
    fd
    tmux
    tree
  ];

  # Homebrew (nix-darwin manages it declaratively)
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
    };
    casks = [
      "alacritty"
      "1password"
      "claude"
    ];
  };

  # macOS defaults
  system.defaults = {
    dock.autohide = true;
    dock.show-recents = false;
    finder.AppleShowAllExtensions = true;
    NSGlobalDomain.AppleInterfaceStyle = "Dark";
    NSGlobalDomain.AppleShowAllExtensions = true;
  };

  # Set hostname
  networking.hostName = hostname;

  # Use zsh as default shell
  programs.zsh.enable = true;

  # Required for nix-darwin
  services.nix-daemon.enable = true;

  # Used for backwards compatibility
  system.stateVersion = 6;
}
```

**Step 2: Commit**

```bash
git add hosts/shared.nix
git commit -m "Add shared nix-darwin host config"
```

---

### Task 4: Create per-host config

**Files:**
- Create: `hosts/Nelsons-MacBook-Pro.nix`

**Step 1: Write hosts/Nelsons-MacBook-Pro.nix**

Thin wrapper — imports shared config, adds machine-specific overrides.

```nix
{ ... }:

{
  # Host-specific overrides go here.
  # Shared config is loaded by flake.nix.
  #
  # Examples:
  #   homebrew.casks = [ "some-work-only-app" ];
  #   environment.systemPackages = [ pkgs.some-tool ];
}
```

**Step 2: Commit**

```bash
git add hosts/Nelsons-MacBook-Pro.nix
git commit -m "Add Nelsons-MacBook-Pro host config"
```

---

### Task 5: Create home-manager config

**Files:**
- Create: `home/default.nix`

**Step 1: Write home/default.nix**

```nix
{ config, pkgs, ... }:

{
  home.stateVersion = "24.11";

  # User packages
  home.packages = with pkgs; [
    emacs-mac-custom
  ];

  # Dotfile symlinks — point directly to repo, not Nix store
  home.file.".config/emacs".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/repos/dotfiles/emacs";

  home.file.".config/alacritty".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/repos/dotfiles/alacritty";

  # Let home-manager manage itself
  programs.home-manager.enable = true;
}
```

**Step 2: Commit**

```bash
git add home/default.nix
git commit -m "Add home-manager config with dotfile symlinks"
```

---

### Task 6: Create emacs-mac overlay

**Files:**
- Create: `overlays/emacs-mac.nix`

**Step 1: Write overlays/emacs-mac.nix**

Override nixpkgs' `emacsMacport` to build from jdtsmith's branch with the
configure flags from the previous manual build.

```nix
final: prev: {
  emacs-mac-custom = prev.emacsMacport.overrideAttrs (old: {
    pname = "emacs-mac-custom";
    version = "30.1-jdtsmith";

    src = prev.fetchFromGitHub {
      owner = "jdtsmith";
      repo = "emacs-mac";
      rev = "emacs-mac-30_1_exp";
      hash = "";  # Will fail on first build — replace with real hash from error
    };

    configureFlags = (old.configureFlags or []) ++ [
      "--with-native-compilation"
      "--with-tree-sitter"
      "--with-rsvg"
      "--enable-mac-app=yes"
      "--enable-mac-self-contained"
    ];

    # Ensure build deps are available
    buildInputs = (old.buildInputs or []) ++ (with prev; [
      tree-sitter
      librsvg
      libgccjit
    ]);

    # Match the CFLAGS from manual build
    env = (old.env or {}) // {
      NIX_CFLAGS_COMPILE = "-DFD_SETSIZE=10000 -D_DARWIN_UNLIMITED_SELECT";
    };
  });
}
```

**Step 2: Commit**

```bash
git add overlays/emacs-mac.nix
git commit -m "Add emacs-mac overlay for jdtsmith branch"
```

---

### Task 7: Whitelist new Nix files in .gitignore

**Files:**
- Modify: `.gitignore`

**Step 1: Add Nix directories to whitelist**

Add to `.gitignore` after the existing config directory entries:

```gitignore
!flake.nix
!flake.lock
!hosts/
!hosts/**
!home/
!home/**
!overlays/
!overlays/**
```

**Step 2: Verify all files are tracked**

Run: `git status`
Expected: no Nix files show as untracked

**Step 3: Commit**

```bash
git add .gitignore
git commit -m "Whitelist Nix flake files in .gitignore"
```

---

### Task 8: First build

**Step 1: Remove existing symlinks**

The existing manual symlinks will conflict with home-manager. Remove them:

```bash
rm ~/.config/emacs
rm ~/.config/alacritty
```

(home-manager will recreate them)

**Step 2: Run nix-darwin build**

```bash
cd ~/repos/dotfiles
nix run nix-darwin -- switch --flake .#Nelsons-MacBook-Pro
```

First run will:
- Download nix-darwin and home-manager
- Build emacs-mac from source (this will take a while)
- Fail on emacs overlay hash — copy the correct hash from the error message,
  paste into `overlays/emacs-mac.nix`, and rerun

**Step 3: Fix emacs overlay hash and rebuild**

After the hash error, update `overlays/emacs-mac.nix` with the real hash,
then rerun:

```bash
nix run nix-darwin -- switch --flake .#Nelsons-MacBook-Pro
```

**Step 4: Verify**

Check symlinks:
```bash
ls -la ~/.config/emacs ~/.config/alacritty
```
Expected: both point to `~/repos/dotfiles/emacs` and `~/repos/dotfiles/alacritty`

Check Emacs launches:
```bash
emacs --version
```

Check Homebrew casks were installed:
```bash
brew list --cask
```
Expected: alacritty, 1password, claude listed

**Step 5: Commit the hash fix**

```bash
git add overlays/emacs-mac.nix
git commit -m "Fix emacs-mac source hash"
```

---

### Task 9: Push and verify

**Step 1: Push to remote**

```bash
cd ~/repos/dotfiles
git push
```

**Step 2: Verify darwin-rebuild works**

Now that nix-darwin is installed, subsequent rebuilds use:

```bash
darwin-rebuild switch --flake ~/repos/dotfiles
```

Run it and confirm no errors.

---

## Post-Implementation: Growing the Config

Once the base works, add incrementally:

- **More casks**: add to `hosts/shared.nix` `homebrew.casks` list
- **More CLI packages**: add to `environment.systemPackages` or `home.packages`
- **More dotfile symlinks**: add `home.file` entries in `home/default.nix`
- **macOS defaults**: add to `system.defaults` in `hosts/shared.nix`
- **New machine**: create `hosts/NewHostname.nix`, add entry to `flake.nix`
- **Shell config**: add zsh/tmux dirs to repo, add symlink entries
