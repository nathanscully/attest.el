{
  description = "attest.el, an Emacs test runner with per-language backends";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, devshell, treefmt-nix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ devshell.flakeModule ];

      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];

      perSystem = { pkgs, ... }:
        let
          emacs = import ./nix/emacs.nix { inherit pkgs; };
          # Config baked into the wrapper, so editors can run
          # `treefmt --stdin <path>` without a treefmt.toml on disk.
          treefmtWrapper = import ./nix/formatter.nix {
            inherit pkgs treefmt-nix;
          };
        in
        {
          # `nix develop` drops into the shell; every command is also
          # reachable as `nix develop -c <name>`.
          devshells = import ./nix/devshell.nix {
            inherit pkgs emacs treefmtWrapper;
          };

          # `nix flake check`: the same commands against a store Emacs with
          # nothing from the host. The vitest integration test skips itself
          # here (the sandbox cannot fetch node_modules); node, cargo and
          # pytest run for real.
          checks.attest = pkgs.stdenv.mkDerivation {
            name = "attest-check";
            src = inputs.self;
            nativeBuildInputs = [ emacs.emacs ] ++ emacs.runners;
            EMACS_TREE_SITTER_GRAMMARS = "${emacs.grammars}/lib";
            buildPhase = ''
              runHook preBuild
              export HOME=$TMPDIR
              ${emacs.scripts.compile}
              ${emacs.scripts.checkdoc}
              ${emacs.scripts.test}
              runHook postBuild
            '';
            installPhase = "touch $out";
          };

          formatter = treefmtWrapper;
        };
    };
}
