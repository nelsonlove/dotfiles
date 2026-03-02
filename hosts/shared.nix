{ pkgs, hostname, ... }:

{
  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "nelson" ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # System packages
  environment.systemPackages = with pkgs; [
    git
    ripgrep
    fd
    tmux
    tree
  ];

  # Homebrew (managed declaratively by nix-darwin)
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

  # Hostname
  networking.hostName = hostname;

  # Shell
  programs.zsh.enable = true;

  # Required for nix-darwin
  services.nix-daemon.enable = true;

  # Backwards compatibility
  system.stateVersion = 6;
}
