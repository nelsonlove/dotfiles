{ pkgs, hostname, ... }:

# Pi 400 NixOS host.
#
# Bootstrap order:
#   1. Flash stock NixOS aarch64 SD image, boot Pi with ethernet.
#   2. At Pi console: `sudo passwd nixos`, or add ~/.ssh/authorized_keys.
#   3. From Mac: `scp pi:/etc/nixos/hardware-configuration.nix ./hardware.nix`
#      (and import it below) — needed so root filesystem device is correct.
#   4. From Mac: `nixos-rebuild switch --flake .#pi400 \
#        --target-host nelson@<dhcp-ip> --build-host localhost --use-remote-sudo`
#   5. At Pi console: `sudo tailscale up --ssh --accept-routes` (interactive auth).
#   6. At Pi console (once on WiFi range): `nmcli device wifi connect myluigi13
#        password '...'` — NM persists this to /etc/NetworkManager/system-connections.
#
# Iteration 2 (later): sops-nix for WiFi PSKs + Tailscale authkey, Obsidian under
# Xvfb, home-manager.

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

  # vault-mcp — local-only MCP server for claude-code on Pi.
  # Source: ~/repos/obsidian-vault-mcp-server (cloned + built once at
  # /home/nelson/repos/vault-mcp). Listens on localhost so no exposure.
  # Iteration 2: package via buildNpmPackage (repo's vault-mcp.nix derivation).
  systemd.services.vault-mcp = {
    description = "Obsidian vault MCP server (local Streamable HTTP)";
    after = [ "network.target" "obsidian-sync.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "nelson";
      Group = "users";
      WorkingDirectory = "/home/nelson/repos/vault-mcp";
      Environment = [
        "VAULT_PATH=/home/nelson/obsidian"
        "PORT=8787"
        "HOST=127.0.0.1"
        "AUTH_ENABLED=false"
        "PATH=/run/current-system/sw/bin"
      ];
      ExecStart = "${pkgs.nodejs_22}/bin/node /home/nelson/repos/vault-mcp/dist/index.js";
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
