# Homebrew inventory as of 2026-03-02
# Review and move items to shared.nix or per-host configs as needed.
# Items already managed are marked with [active].
#
# This file is not imported by anything — it's just a reference.

{
  casks = [
    # --- Active ---
    # "alacritty"           [active] shared.nix
    # "claude"              [active] shared.nix
    # "claude-code"         [active] shared.nix
    # "daisydisk"           [active] shared.nix
    # "font-iosevka"        [active] shared.nix
    # "hazel"               [active] shared.nix
    # "karabiner-elements"  [active] shared.nix
    # "obsidian"            [active] shared.nix
    # "docker"              [active] Nelsons-MacBook-Pro.nix

    # --- To review ---
    # "1password"
    # "aerospace"
    # "alfred"
    # "applite"
    # "arduino-ide"
    # "audacity"
    # "audio-hijack"
    # "banktivity"
    # "bibdesk"
    # "blackhole-2ch"
    # "blender"
    # "bookends"
    # "calibre"
    # "chatgpt"
    # "chromium"
    # "cirrus"
    # "clipgrab"
    # "cork"
    # "curseforge"
    # "cursor"
    # "dash"
    # "discord"
    # "docker-desktop"
    # "firefox"
    # "font-et-book"
    # "font-fantasque-sans-mono-nerd-font"
    # "font-fira-code"
    # "font-inter"
    # "font-iosevka-aile"
    # "font-merriweather"
    # "font-optician-sans"
    # "font-roboto-mono"
    # "font-source-code-pro"
    # "font-victor-mono"
    # "font-yrsa"
    # "git-credential-manager"
    # "github"
    # "gitkraken"
    # "godot"
    # "google-chrome"
    # "gstreamer-runtime"
    # "handbrake"
    # "handbrake-app"
    # "hot"
    # "imazing"
    # "inform"
    # "jetbrains-toolbox"
    # "kegworks"
    # "knockknock"
    # "little-snitch"
    # "loopback"
    # "macfuse"
    # "mactex-no-gui"
    # "mailmate"
    # "malwarebytes"
    # "mark-text"
    # "material-colors"
    # "micro-snitch"
    # "miniconda"
    # "ngrok"
    # "onyx"
    # "openclaw"
    # "pearcleaner"
    # "powerphotos"
    # "qflipper"
    # "qlmarkdown"
    # "raspberry-pi-imager"
    # "sirimote"
    # "soulver"
    # "steam"
    # "syncthing"
    # "syncthing-app"
    # "synthesia"
    # "tailscale-app"
    # "the-unarchiver"
    # "tomatobar"
    # "transmission"
    # "transmit"
    # "ultimaker-cura"
    # "usr-sse2-rdm"
    # "utm"
    # "vagrant"
    # "vlc"
    # "wine-stable"
    # "xquartz"
    # "zoom"
  ];

  formulae = [
    # --- Active (in environment.systemPackages as Nix pkgs) ---
    # coreutils             [active]
    # fd                    [active]
    # findutils             [active]
    # gh                    [active]
    # git                   [active]
    # git-lfs               [active]
    # gnu-sed               [active]
    # jq                    [active]
    # mas                   [active]
    # ripgrep               [active]
    # tmux                  [active]
    # tree                  [active]
    # wget                  [active]

    # --- Directly used (to review) ---
    # "asciinema"
    # "autojump"
    # "awscli"
    # "azure-cli"
    # "bfg"
    # "black"
    # "bpython"
    # "bun"
    # "claude-squad"
    # "cmake"
    # "colordiff"
    # "cookiecutter"
    # "direnv"
    # "dive"
    # "docker-compose"
    # "exiftool"
    # "ffmpeg"
    # "flake8"
    # "fortune"
    # "fzf"
    # "git-delta"
    # "git-extras"
    # "go"
    # "grip"
    # "himalaya"
    # "huggingface-cli"
    # "hunspell"
    # "imagemagick"
    # "ipython"
    # "isort"
    # "jupyterlab"
    # "k9s"
    # "ledger"
    # "llvm"
    # "localstack"
    # "micro"
    # "mosh"
    # "multimarkdown"
    # "nmap"
    # "node"
    # "obsidian-cli"
    # "ollama"
    # "pandoc"
    # "pass"
    # "pipx"
    # "pnpm"
    # "poetry"
    # "pre-commit"
    # "prettier"
    # "proselint"
    # "pyenv"
    # "pylint"
    # "pyright"
    # "python-lsp-server"
    # "r"
    # "redis"
    # "ruff"
    # "rust"
    # "sbcl"
    # "semgrep"
    # "serverless"
    # "shellcheck"
    # "shfmt"
    # "skhd"
    # "sqlmap"
    # "stripe-cli"
    # "task"
    # "terraform"
    # "tesseract"
    # "thefuck"
    # "uv"
    # "yabai"
    # "yarn"
    # "yq"

    # --- Dependencies (pulled in automatically, don't add) ---
    # Everything else (libpng, cairo, glib, protobuf, qt, etc.)
  ];
}
