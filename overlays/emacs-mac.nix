final: prev: {
  emacs-mac-custom = prev.emacs-macport.overrideAttrs (old: {
    pname = "emacs-mac-custom";
    version = "30.1-jdtsmith";

    src = prev.fetchFromGitHub {
      owner = "jdtsmith";
      repo = "emacs-mac";
      rev = "emacs-mac-30_1_exp";
      hash = "sha256-jqj0rmVepGEcDKzvt6B3wYfvEFyum+ZMzkCf+M5gj2s=";
    };

    configureFlags = (old.configureFlags or []) ++ [
      "--with-native-compilation"
      "--with-tree-sitter"
      "--with-rsvg"
      "--enable-mac-app=${placeholder "out"}/Applications"
    ];

    buildInputs = (old.buildInputs or []) ++ (with prev; [
      tree-sitter
      librsvg
      libgccjit
    ]);

    env = (old.env or {}) // {
      NIX_CFLAGS_COMPILE = "-DFD_SETSIZE=10000 -D_DARWIN_UNLIMITED_SELECT";
    };
  });
}
