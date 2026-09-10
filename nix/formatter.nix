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
  ];

  programs = {
    nixpkgs-fmt.enable = true;
    prettier.enable = true;
    taplo.enable = true;
    yamlfmt.enable = true;
    mdformat.enable = true;
  };

  # mdformat owns Markdown, not prettier: it leaves tables and paragraph
  # wrapping alone, where prettier pads every cell to the widest row.
  # `--wrap keep` is the default and preserves the hand-wrapped prose;
  # `--number` keeps ordered lists consecutively numbered in the source,
  # which the reading-order and findings lists read better for.
  settings.formatter.mdformat.options = [ "--number" "--wrap" "keep" ];
  settings.formatter.prettier.excludes = [ "*.md" ];

  # No Elisp formatter ships with treefmt, so use the indentation Emacs
  # itself applies. Tabs are never used in this codebase, hence the
  # indent-tabs-mode binding.
  settings.formatter.elisp = {
    command = "${pkgs.emacs-nox}/bin/emacs";
    options = [ "-Q" "--batch" "-l" "scripts/format.el" ];
    includes = [ "*.el" ];
  };
}).config.build.wrapper
