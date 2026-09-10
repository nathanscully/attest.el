{ pkgs, treefmt-nix }:

(treefmt-nix.lib.evalModule pkgs {
  projectRootFile = "flake.nix";

  settings.global.excludes = [
    "flake.lock"
    "LICENSE"
    "*.jsonl"
    "**/node_modules/**"
    "**/target/**"
    ".claude/**"
    # Test data, not source. Parser tests replay the recorded events byte
    # for byte, and discovery tests assert the exact line a test sits on,
    # so a formatter moving a line breaks the suite for no gain.
    "test/fixtures/**"
    "stress/**"
    # Historical records of reviews as they were written.
    "docs/reviews/**"
    # Prose is hand-wrapped at 72 columns and the tables are written to
    # read as source. Prettier pads every cell to the widest row, which is
    # churn rather than formatting.
    "*.md"
  ];

  programs = {
    nixpkgs-fmt.enable = true;
    prettier.enable = true;
    taplo.enable = true;
    yamlfmt.enable = true;
  };

  # No Elisp formatter ships with treefmt, so use the indentation Emacs
  # itself applies. Tabs are never used in this codebase, hence the
  # indent-tabs-mode binding.
  settings.formatter.elisp = {
    command = "${pkgs.emacs-nox}/bin/emacs";
    options = [ "-Q" "--batch" "-l" "scripts/format.el" ];
    includes = [ "*.el" ];
  };
}).config.build.wrapper
