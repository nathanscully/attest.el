{
  description = "neotest.el, an Emacs test runner with per-language backends";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (s: f (import nixpkgs { system = s; }));

      # Everything the Makefile needs: a clean batch Emacs, the five grammars
      # test-helper.el loads via EMACS_TREE_SITTER_GRAMMARS, and the four
      # runners the integration tests spawn.
      toolchain = pkgs: rec {
        emacs = pkgs.emacs-nox;
        grammars = pkgs.emacsPackages.treesit-grammars.with-grammars (g: with g; [
          tree-sitter-typescript
          tree-sitter-tsx
          tree-sitter-javascript
          tree-sitter-rust
          tree-sitter-python
        ]);
        runners = [
          pkgs.nodejs
          pkgs.cargo
          pkgs.rustc
          (pkgs.python3.withPackages (ps: [ ps.pytest ]))
        ];
      };
    in
    {
      # `nix develop -c make all` / `-c make stress`. pnpm is here for the
      # vitest fixture and stress project installs; the check below cannot
      # fetch node_modules, so vitest coverage lives in this shell.
      devShells = forAllSystems (pkgs:
        let t = toolchain pkgs; in {
          default = pkgs.mkShell {
            packages = [ t.emacs pkgs.gnumake pkgs.pnpm ] ++ t.runners;
            env.EMACS_TREE_SITTER_GRAMMARS = "${t.grammars}/lib";
          };
        });

      # `nix flake check`: byte-compile (warnings as errors), checkdoc and ert
      # against a store Emacs with nothing from the host. The vitest
      # integration test skips itself (no node_modules in the sandbox); the
      # node, cargo and pytest integration tests run for real.
      checks = forAllSystems (pkgs:
        let t = toolchain pkgs; in {
          neotest = pkgs.stdenv.mkDerivation {
            name = "neotest-make-all";
            src = self;
            nativeBuildInputs = [ t.emacs pkgs.gnumake ] ++ t.runners;
            EMACS_TREE_SITTER_GRAMMARS = "${t.grammars}/lib";
            buildPhase = ''
              runHook preBuild
              export HOME=$TMPDIR
              make all
              runHook postBuild
            '';
            installPhase = "touch $out";
          };
        });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);
    };
}
