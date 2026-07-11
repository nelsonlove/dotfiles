{ config, lib, pkgs, ... }:

let
  # Canonical locations, declared once — mirrors DOTFILES / SECRETS_DIR in zsh/.zshenv.
  dotfiles = "${config.home.homeDirectory}/repos/dotfiles";
  secretsDir = "${config.home.homeDirectory}/Documents/00-09 System/09 Secrets & credentials/09.11 Secrets";
in
{
  home.username = "nelson";
  home.homeDirectory = lib.mkForce "/Users/nelson";
  home.stateVersion = "24.11";

  # User packages
  home.packages = with pkgs; [
    emacs-mac-custom
    symbola
  ];

  # Dotfile symlinks — mkOutOfStoreSymlink points directly to repo,
  # not the Nix store. Edits are live, no rebuild needed.
  home.file.".config/doom".source =
    config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/doom";

  home.file.".config/alacritty".source =
    config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/alacritty";

  home.file.".config/tmux".source =
    config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/tmux";

  home.file.".config/git".source =
    config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/git";

  home.file.".config/micro".source =
    config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/micro";

  home.file.".config/karabiner/karabiner.json".source =
    config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/karabiner/karabiner.json";

  home.file.".config/zsh".source =
    config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/zsh";

  home.file.".zshrc".source =
    config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/zsh/.zshrc";

  home.file.".zprofile".source =
    config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/zsh/.zprofile";

  # Secrets — symlinked from iCloud Drive (09.11 Secrets)
  home.file.".config/gh/hosts.yml".source =
    config.lib.file.mkOutOfStoreSymlink
      "${secretsDir}/gh/hosts.yml";

  home.file.".ssh".source =
    config.lib.file.mkOutOfStoreSymlink
      "${secretsDir}/ssh";

  home.file.".config/aws/config".source =
    config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/aws/config";

  home.file.".config/aws/credentials".source =
    config.lib.file.mkOutOfStoreSymlink
      "${secretsDir}/aws/credentials";

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

  # Doom Emacs — clone framework and install if not present
  home.activation.doomEmacs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.emacs.d/bin" ]; then
      ${pkgs.git}/bin/git clone --depth 1 https://github.com/doomemacs/doomemacs "$HOME/.emacs.d"
      "$HOME/.emacs.d/bin/doom" install --no-config
    fi
  '';

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
