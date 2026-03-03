{ config, lib, pkgs, ... }:

{
  home.username = "nelson";
  home.homeDirectory = lib.mkForce "/Users/nelson";
  home.stateVersion = "24.11";

  # User packages
  home.packages = with pkgs; [
    emacs-mac-custom
  ];

  # Dotfile symlinks — mkOutOfStoreSymlink points directly to repo,
  # not the Nix store. Edits are live, no rebuild needed.
  home.file.".config/emacs".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/repos/dotfiles/emacs";

  home.file.".config/alacritty".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/repos/dotfiles/alacritty";

  home.file.".config/tmux".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/repos/dotfiles/tmux";

  home.file.".config/git".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/repos/dotfiles/git";

  home.file.".config/micro".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/repos/dotfiles/micro";

  home.file.".config/karabiner/karabiner.json".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/repos/dotfiles/karabiner/karabiner.json";

  home.file.".config/zsh".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/repos/dotfiles/zsh";

  home.file.".zshrc".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/repos/dotfiles/zsh/.zshrc";

  home.file.".zprofile".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/repos/dotfiles/zsh/.zprofile";

  # Secrets — symlinked from iCloud Drive (06.04 Secrets)
  home.file.".config/gh/hosts.yml".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/Documents/00-09 Meta/06 Digital tools/06.04 Secrets/gh/hosts.yml";

  home.file.".ssh".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/Documents/00-09 Meta/06 Digital tools/06.04 Secrets/ssh";

  home.file.".config/aws/config".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/repos/dotfiles/aws/config";

  home.file.".config/aws/credentials".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/Documents/00-09 Meta/06 Digital tools/06.04 Secrets/aws/credentials";

  # GitHub CLI
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      editor = "emacsclient";
      prompt = "enabled";
      aliases = { co = "pr checkout"; };
    };
  };

  # Emacs daemon
  launchd.agents.emacs-daemon = {
    enable = true;
    config = {
      ProgramArguments = [
        "/Applications/Emacs.app/Contents/MacOS/Emacs"
        "--daemon"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      Label = "org.gnu.emacs.daemon";
    };
  };

  # Let home-manager manage itself
  programs.home-manager.enable = true;
}
