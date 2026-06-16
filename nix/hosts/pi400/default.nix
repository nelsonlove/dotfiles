{ pkgs, hostname, inputs, ... }:

let
  # vault-mcp packaged from the upstream repo (see flake.nix vault-mcp-src
  # input). Repo's derivation is system-portable; we callPackage it here so it
  # builds for aarch64-linux against this host's pkgs set.
  vault-mcp = pkgs.callPackage "${inputs.vault-mcp-src}/nix/pkgs/vault-mcp.nix" { };
in

# Pi 400 NixOS host.
#
# Bootstrap order (only when re-flashing or bringing up a new Pi):
#   1. Flash stock NixOS aarch64 SD image, boot Pi with ethernet.
#   2. At Pi console: `passwd nixos` to set a temp password, then
#      `ssh-copy-id nixos@<dhcp-ip>` from the Mac.
#   3. SSH in and run `sudo nixos-generate-config --show-hardware-config`;
#      copy output into ./hardware.nix (it normally won't change between
#      images of the same NixOS release).
#   4. Write the Tailscale authkey to /etc/tailscale.authkey (mode 0600 root).
#   5. Build + switch from the UTM aarch64 NixOS VM:
#        nixos-rebuild switch --flake .#pi400 \
#          --target-host nelson@<dhcp-ip> --use-remote-sudo
#   6. At Pi (once in WiFi range): `nmcli device wifi connect myluigi13
#      password '...'` — NM persists this with 0600 perms.
#
# Iteration 3 (deferred): sops-nix for the Tailscale authkey + WiFi PSKs;
# declarative obsidian-headless install (blocked on upstream pnpm-lock).

{
  imports = [ ./hardware.nix ];

  networking.hostName = hostname;
  time.timeZone = "America/New_York";

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (pkgs.lib.getName pkg) [ "obsidian" "claude-code" ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "@wheel" ];
  };

  # Bootloader for Raspberry Pi (no GRUB — use the SD's extlinux setup)
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # Networking — NM owns WiFi (uses wpa_supplicant as its backend).
  # Profiles set up imperatively once via nmcli.
  networking.networkmanager.enable = true;

  # Users
  users.users.nelson = {
    isNormalUser = true;
    description = "Nelson";
    extraGroups = [ "wheel" "networkmanager" "video" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILXHbH6xriFbjHuXMWDa8M8QTzZfnMZ+hHVTuKyw3LBT nelson@wham.studio"
    ];
  };
  security.sudo.wheelNeedsPassword = false;
  programs.zsh.enable = true;

  # SSH — keys only
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Tailscale — authKeyFile is loaded once at first up; subsequent boots
  # use the persisted machine state. File written out-of-band, mode 0600 root.
  services.tailscale = {
    enable = true;
    authKeyFile = "/etc/tailscale.authkey";
    extraUpFlags = [ "--ssh" "--accept-routes" ];
  };

  # Packages
  environment.systemPackages = with pkgs; [
    claude-code
    git
    vim
    ripgrep
    fd
    jq
    htop
    tmux
    tree
    nodejs_22  # for obsidian-headless (npm-installed under nelson)
  ];

  # Obsidian Sync via the official headless CLI (`ob`). One-time bootstrap:
  #   npm config set prefix ~/.npm-global
  #   npm install -g obsidian-headless
  #   ob login                                    # interactive
  #   ob sync-list-remote                         # confirm vault name
  #   mkdir -p ~/obsidian && cd ~/obsidian
  #   ob sync-setup --vault "<name>"
  #   sudo systemctl enable --now obsidian-sync
  systemd.services.obsidian-sync = {
    description = "Obsidian Sync (headless ob daemon)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "nelson";
      Group = "users";
      WorkingDirectory = "/home/nelson/obsidian";
      Environment = [
        "HOME=/home/nelson"
        "PATH=/home/nelson/.npm-global/bin:/run/current-system/sw/bin"
      ];
      ExecStart = "/home/nelson/.npm-global/bin/ob sync --continuous";
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };

  # vault-mcp — local-only MCP server for claude-code on Pi. Sourced from the
  # upstream repo's derivation via flake input (see top of file). Listens on
  # localhost only — no exposure, no auth.
  systemd.services.vault-mcp = {
    description = "Obsidian vault MCP server (local Streamable HTTP)";
    # vault-mcp is a peer of obsidian-sync — both read /home/nelson/obsidian;
    # vault-mcp can serve whatever is on disk independently. Just need network
    # (for the listen socket) before we start.
    after = [ "network.target" ];
    wants = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "nelson";
      Group = "users";
      Environment = [
        "VAULT_PATH=/home/nelson/obsidian"
        "PORT=8787"
        "HOST=127.0.0.1"
        "AUTH_ENABLED=false"
      ];
      ExecStart = "${vault-mcp}/bin/vault-mcp";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # Swap — 4 GB RAM is tight when nix evaluates anything large.
  # Build offloading to the Mac should mean this rarely matters, but
  # cheap insurance.
  swapDevices = [{
    device = "/swapfile";
    size = 4096;
  }];

  system.stateVersion = "25.05";
}
