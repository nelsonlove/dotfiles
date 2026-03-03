{ pkgs, hostname, ... }:

{
  # Determinate Nix manages its own daemon — don't let nix-darwin conflict
  nix.enable = false;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # System packages
  environment.systemPackages = with pkgs; [
    coreutils
    fd
    findutils
    gh
    git
    git-lfs
    gnused
    jq
    mas
    ripgrep
    tmux
    tree
    wget
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
      "claude"
      "claude-code"
      "daisydisk"
      "font-iosevka"
      "hazel"
      "karabiner-elements"
      "obsidian"
    ];
    masApps = {
      "Day One" = 1055511498;
      "Gemini 2" = 1090488118;
      "Numbers" = 409203825;
      "OmniFocus 4" = 1542143627;
      "Pages" = 409201541;
    };
  };

  # macOS defaults
  system.defaults = {
    # Dock
    dock.autohide = true;
    dock.autohide-delay = 0.0;
    dock.autohide-time-modifier = 0.15;
    dock.launchanim = false;
    dock.mru-spaces = false;
    dock.show-recents = false;
    dock.showAppExposeGestureEnabled = true;
    dock.expose-animation-duration = 0.1;
    dock.persistent-apps = [
      "/System/Applications/Launchpad.app"
      "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"
      "/System/Applications/Messages.app"
      "/System/Applications/Mail.app"
      "/System/Applications/Calendar.app"
      "/System/Applications/Notes.app"
      "/System/Applications/Music.app"
      "/System/Applications/System Settings.app"
      # Enable after homebrew.enable = true and emacs builds:
      # "/Applications/Alacritty.app"
      # "/Applications/Emacs.app"
      # "/Applications/Obsidian.app"
      # "/Applications/OmniFocus.app"
    ];

    # Finder
    finder.AppleShowAllExtensions = true;
    finder.FXEnableExtensionChangeWarning = false;
    finder.FXDefaultSearchScope = "SCcf";
    finder.FXPreferredViewStyle = "Nlsv";
    finder.NewWindowTarget = "Home";
    finder._FXSortFoldersFirst = true;
    finder._FXShowPosixPathInTitle = true;
    finder.QuitMenuItem = true;
    finder.ShowPathbar = true;
    finder.ShowStatusBar = true;

    # Trackpad
    trackpad.Clicking = true;
    trackpad.TrackpadThreeFingerDrag = true;
    trackpad.TrackpadRightClick = true;

    # Screenshots
    screencapture.location = "~/Desktop";
    screencapture.disable-shadow = true;

    # Menu bar
    controlcenter.Bluetooth = true;
    controlcenter.Sound = true;

    # Login
    loginwindow.GuestEnabled = false;

    # Gatekeeper
    LaunchServices.LSQuarantine = false;

    # Global
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      AppleInterfaceStyleSwitchesAutomatically = true;
      "com.apple.mouse.tapBehavior" = 1;

      # Disable autocorrect nonsense
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;

      # Save/print dialogs expanded by default
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      PMPrintingExpandedStateForPrint = true;
      PMPrintingExpandedStateForPrint2 = true;

      # Save to disk, not iCloud
      NSDocumentSaveNewDocumentsToCloud = false;
    };

    # App-specific
    CustomUserPreferences = {
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      "com.apple.ImageCapture" = {
        disableHotPlug = true;
      };
      "com.apple.TextEdit" = {
        RichText = 0;
      };
      # Requires Full Disk Access for Terminal to write to Safari's container
      "com.apple.Safari" = {
        IncludeDevelopMenu = true;
        ShowFullURLInSmartSearchField = true;
        AutoOpenSafeDownloads = false;
      };
    };
  };

  # User
  users.users.nelson = {
    name = "nelson";
    home = "/Users/nelson";
  };

  # Hostname
  networking.hostName = hostname;

  # Touch ID for sudo (and Apple Watch)
  security.pam.services.sudo_local.touchIdAuth = true;

  # Primary user (required for system.defaults, homebrew, etc.)
  system.primaryUser = "nelson";

  # Shell
  programs.zsh.enable = true;

  # Backwards compatibility
  system.stateVersion = 6;
}
