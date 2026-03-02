# Migration tracker for ~/.config/install/macos.sh
# Items from the old setup script that haven't been moved to nix-darwin yet.
# This file is not imported — it's a reference for future work.

{
  # --- Not yet migrated ---

  # File associations (duti)
  # Needs: `duti` in system packages, post-activation script
  # duti -s org.gnu.Emacs public.plain-text editor
  # duti -s org.gnu.Emacs public.source-code editor
  # duti -s org.gnu.Emacs public.script editor
  # duti -s org.gnu.Emacs public.data editor
  # duti -s org.gnu.Emacs public.xml editor
  # duti -s org.gnu.Emacs public.shell-script editor
  # duti -s org.gnu.Emacs .md .py .toml .ipynb .log editor
  # duti -s org.gnu.Emacs com.apple.property-list editor
  # duti -s org.videolan.vlc avi flac flv mkv mov mp3 mp4 mpg wav wmv viewer

  # Show ~/Library and /Volumes
  # chflags nohidden ~/Library
  # sudo chflags nohidden /Volumes

  # Startup chime
  # sudo nvram StartupMute=%00

  # Reset Launchpad
  # find ~/Library/Application\ Support/Dock -maxdepth 1 -name "*.db" -delete

  # Dock persistent apps (see below)
  # dockutil --remove FaceTime TV Numbers Pages Keynote News
  # dockutil --add /Applications/Alacritty.app
  # dockutil --add /Applications/Emacs.app

  # Transmission settings (if still using)
  # UseIncompleteDownloadFolder, DownloadLocationConstant, etc.

  # Messages: disable smart quotes
  # defaults write com.apple.messageshelper.MessageController
  #   SOInputLineSettings -dict-add "automaticQuoteSubstitutionEnabled" -bool false

  # --- Decided not to migrate ---

  # NSRequiresAquaSystemAppearance — Mojave-era hack, conflicts with auto dark mode
  # NSUserKeyEquivalents for System Settings — fragile, breaks across macOS versions
  # Minikube/Docker socket setup — using Docker Desktop now
  # Dash/Transmit/Alfred license copying — manual or revisit later

  # --- Nice to have (from commented section) ---

  # Touch ID for sudo (needs SIP consideration)
  # Finder: NewWindowTarget = "PfHm" (open home by default)
  # Finder: FXPreferredViewStyle = "Nlsv" (list view)
  # Hot corners (currently unused)
  # Secure keyboard entry in Terminal
  # Hide /opt
  # Time Machine: DoNotOfferNewDisksForBackup
}
