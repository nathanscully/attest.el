{ pkgs }:

rec {
  # A clean batch Emacs, the five grammars test-helper.el loads through
  # EMACS_TREE_SITTER_GRAMMARS, and the four runners the integration tests
  # spawn.
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

  # Byte-compile order is load-bearing: a file must compile after everything
  # it requires, or warnings-as-errors fires on a forward reference.
  core = [
    "lisp/core/attest-model.el"
    "lisp/core/attest-backend.el"
    "lisp/core/attest-discovery.el"
    "lisp/core/attest-results.el"
    "lisp/core/attest-run.el"
    "lisp/backends/shared/attest-javascript.el"
  ];

  sources = core ++ [
    "lisp/attest.el"
    "lisp/backends/node/attest-node.el"
    "lisp/backends/vitest/attest-vitest.el"
    "lisp/backends/cargo/attest-rust.el"
    "lisp/backends/pytest/attest-pytest.el"
    "lisp/consumers/attest-flymake.el"
    "lisp/consumers/attest-status.el"
    "lisp/consumers/attest-list.el"
    "lisp/attest-all.el"
  ];

  assets = [
    "lisp/backends/node/attest-node-reporter.mjs"
    "lisp/backends/vitest/attest-vitest-reporter.mjs"
    "lisp/backends/pytest/attest_pytest.py"
  ];

  directories = [
    "lisp"
    "lisp/core"
    "lisp/backends/shared"
    "lisp/backends/node"
    "lisp/backends/vitest"
    "lisp/backends/cargo"
    "lisp/backends/pytest"
    "lisp/consumers"
    "test"
  ];

  version = "0.1.0";

  inherit (pkgs.lib) concatStringsSep;

  load = concatStringsSep " " (
    [ "--eval '(setq load-prefer-newer t)'" ]
    ++ map (d: "-L ${d}") directories
  );

  sourceArgs = concatStringsSep " " sources;
  assetArgs = concatStringsSep " " assets;

  # Every command is one batch Emacs. Written once here so the dev shell and
  # the sandboxed check cannot drift apart.
  scripts = {
    compile = ''
      emacs -Q --batch ${load} -l scripts/compile.el ${sourceArgs}
    '';

    checkdoc = ''
      emacs -Q --batch ${load} -l test/run-checkdoc.el ${sourceArgs}
    '';

    test = ''
      emacs -Q --batch ${load} -l test-helper \
        $(for f in test/*-test.el; do
            [ "$f" = test/attest-stress-test.el ] || printf -- '-l %s ' "$f"
          done) \
        -f ert-run-tests-batch-and-exit
    '';

    stress = ''
      emacs -Q --batch ${load} -l test-helper \
        -l test/attest-stress-test.el -f ert-run-tests-batch-and-exit
    '';

    package = ''
      emacs -Q --batch -l scripts/package.el ${sourceArgs} ${assetArgs}
      tar -cf build/attest-${version}.tar -C build attest-${version}
    '';

    package-test = ''
      emacs -Q --batch -l test/package-smoke.el build/attest-${version}.tar
    '';

    clean = ''
      rm -rf build
    '';
  };
}
