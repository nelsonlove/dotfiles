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

  home.file.".config/karabiner".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/repos/dotfiles/karabiner";

  # Let home-manager manage itself
  programs.home-manager.enable = true;
}
