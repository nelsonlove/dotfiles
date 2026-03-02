final: prev: {
  emacs-mac-custom = prev.emacs-macport.overrideAttrs (old: {
    pname = "emacs-mac-custom";
    version = "30.1-jdtsmith";

    src = prev.fetchFromGitHub {
      owner = "jdtsmith";
      repo = "emacs-mac";
      rev = "emacs-mac-30_1_exp";
      hash = "";  # First build will fail — replace with hash from error output
    };

    configureFlags = (old.configureFlags or []) ++ [
      "--with-native-compilation"
      "--with-tree-sitter"
      "--with-rsvg"
      "--enable-mac-app=yes"
      "--enable-mac-self-contained"
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
