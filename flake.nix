{
  description = "attest.el, an Emacs test runner with per-language backends";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, devshell, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ devshell.flakeModule ];

      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];

      perSystem = { pkgs, self', ... }:
        let
          emacs = import ./nix/emacs.nix { inherit pkgs; };
        in
        {
          # `nix develop` drops into the shell; every command is also
          # reachable as `nix develop -c <name>`.
          devshells = import ./nix/devshell.nix { inherit pkgs emacs; };

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

          formatter = pkgs.nixpkgs-fmt;
        };
    };
}
