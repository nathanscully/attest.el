# attest.el

Emacs test runner with per-language backends. Core is built-ins only and
requires an Emacs built with tree-sitter. Four backends: `node --test`,
vitest, `cargo test`, pytest. Three consumers: flymake, fringe status,
tabulated results list.

Read in this order before changing anything:

1. `DESIGN.md`: backend contract, data model, run lifecycle, which
   built-in provides each feature, what is deliberately not built.
2. `ASSESSMENT.md`: what works, where the built-ins thesis strains,
   the tree-sitter decision, comparison with verdict and test-cockpit.
3. `lisp/core/`: the core, split into model, backend registry,
   discovery, results and run lifecycle. `lisp/attest.el` is the
   command surface over it; everything else is a backend or a consumer.

## Layout

| path | role |
|---|---|
| `lisp/core/` | model, backend registry, discovery, results and run lifecycle |
| `lisp/backends/{node,vitest,cargo,pytest}/` | framework backends and bundled reporters/plugins |
| `lisp/backends/shared/` | shared JavaScript discovery/parser helpers |
| `lisp/consumers/` | flymake, fringe status and tabulated results consumers |
| `lisp/attest-all.el` | one entry point that loads the core, backends and consumers |
| `test/` | ert tests; parser tests replay `test/fixtures/*-events.jsonl`, one integration test per runner |
| `stress/` | one real project per runner (`node`, `vitest`, `cargo`, `pytest`); `test/attest-stress-test.el` runs them via the `stress` command |
| `flake.nix` | flake-parts entry point; dev shell, commands and `nix flake check` |
| `assets/live-tlox.png` | screenshot of a live run in the daemon |
| `nix/` | `emacs.nix` (toolchain, ordered source list), `devshell.nix` (the commands), `formatter.nix` (treefmt) |
| `scripts/compile.el` | byte-compiles as a lint, discarding the bytecode |
| `scripts/format.el` | reindents Elisp, the formatter treefmt lacks |
| `scripts/package.el` | stages the package, naming it from `attest.el`'s version |
| `docs/` | domain vocabulary (`CONTEXT.md`) and, under `reviews/`, the reviews and 1.0 roadmap |
| `scratch/` | gitignored working notes (`PLAN.md`) |

## Build and test

The dev shell owns the commands; there is no Makefile. `nix develop`
drops into the shell and prints them, `menu` lists them all, and each is
also reachable without entering the shell.

```sh
nix develop -c check         # compile (warnings are errors), checkdoc, ert
nix develop -c ert           # the ert suite only
nix develop -c stress        # live runs against stress/; not part of check
nix develop -c package       # stage the installable tar with autoloads
nix develop -c package-test  # install that tar into a clean Emacs
nix develop -c clean         # drop build/
nix flake check              # the same gate on a clean Emacs in the sandbox
```

`nix/emacs.nix` holds the toolchain and the ordered source list every
command compiles, so the shell and the sandboxed check cannot drift.
`nix/devshell.nix` defines the commands. Byte-compile order is
load-bearing: a file must compile after everything it requires. The ert
command is named `ert`, not `test`, because a shell builtin of that name
would shadow it and silently succeed.

There is no build. Emacs loads attest from source, so `compile` is a
lint: `scripts/compile.el` runs the byte-compiler with warnings as errors
and writes the bytecode to a temporary directory it then deletes. The
diagnostics are the point, and an `.elc` left in the tree would only wait
to shadow an edited source and report a false pass. Bytecode belongs in
a user's install, where `package-install-file` produces it.

The version lives in one place, `lisp/attest.el`'s `;; Version:` header.
`scripts/package.el` reads it, names the staged directory after it and
prints that name for the shell to archive, so no Nix file or command
spells a version out.

`fmt` runs treefmt (`nix/formatter.nix`): nixpkgs-fmt, prettier for JS and
JSON, taplo for TOML, yamlfmt, mdformat for Markdown, and
`scripts/format.el` for Elisp, which applies the indentation Emacs itself
would with tabs disabled. Markdown goes through mdformat rather than
prettier because it leaves tables and paragraph wrapping alone; `--number`
keeps ordered lists numbered in the source. `test/fixtures/` and
`stress/` are excluded, being test data whose exact lines the suite
asserts on.

The stress suite spawns every runner against the projects under
`stress/` and checks what the fixtures cannot: id parity between
discovery and the runner over 30 to 50 files each, that a single target
yields one result and a namespace target its subtree, that
rerun-failed reproduces the failed set, 500-test files, and a mean
discovery cost per file under 60 ms. Each project has hand-written
edge cases (`naming`, `hooks`, `edge`) and committed bulk files. Files
named `dynamic` hold runtime-generated names; their parity tests are
declared `:expected-result :failed` and flip when that gap closes. Add
a new edge case as a committed file, never a generator. `stress/vitest`
needs `pnpm install` once.

The flake pins the whole toolchain: Emacs 30 with the five grammars
(exported as `EMACS_TREE_SITTER_GRAMMARS`), node, cargo, pytest and
pnpm. `nix flake check` runs compile, checkdoc and ert in the build
sandbox against that clean Emacs, so it catches host assumptions the
daemon hides.
The sandbox cannot fetch node_modules, so the vitest integration test
skips there; run the suite in the dev shell for vitest coverage.
CI (`.github/workflows/ci.yml`) runs `nix flake check` on Linux and
macOS and `check` then `stress` in the dev shell; setting the
`CACHIX_CACHE` repo variable and `CACHIX_AUTH_TOKEN` secret turns on
cachix, and without them the cachix steps are skipped.

Requirements on the machine (`nix develop` provides all of it):

- Emacs 30+ with tree-sitter. Grammars for `typescript`, `tsx`,
  `javascript`, `rust`, `python`. Set `EMACS_TREE_SITTER_GRAMMARS` to
  the directory holding `libtree-sitter-*.dylib` if Emacs does not find
  them; `test/test-helper.el` reads it.
- node (integration test), cargo (integration test; first run compiles
  `test/fixtures/rs`), pytest on PATH (integration test; skipped if
  absent), `pnpm install` in `test/fixtures/vitest` for the vitest
  integration test (skipped if `node_modules/.bin/vitest` is absent).

On this machine pytest is not on PATH, so run the commands through
`nix develop -c ...` rather than from a bare shell.

If `NODE_OPTIONS` is set in your shell it can break `node --test`;
use `env -u NODE_OPTIONS node ...` when testing by hand.

## Conventions

- `lexical-binding: t`, prefix `attest-`, private names `attest--`.
- No inline comments; docstrings on every definition; checkdoc clean.
- No third-party dependencies in core or backends. Built-ins only.
- Backends never report where a test is. Core fills `:line`, `:column`
  and `:type` from the discovered position in `attest--record`.
- Ids are `FILE::name::name`. Discovery and the runner must agree; every
  backend has a test asserting the id sets match.
- Run scopes are `file`, `project` and `targets`. Run-at-point and
  rerun-failed are both `targets` runs; backends build one selector per
  target from its `:type`.
- Consumers subscribe to the abnormal hooks `attest-run-started-functions`,
  `attest-result-functions` and `attest-run-finished-functions`.
- Support Emacs 30 and 31. Avoid 31-only calls (grouped
  `treesit-query-capture`, flymake list messages); checkdoc runs with
  the experimental verb check off so both versions agree.
- Parser tests run on recorded fixtures, never on a live process. Keep
  one integration test per runner that spawns the real thing and
  `skip-unless` it is installed.
- Record a fixture by running the runner with the bundled reporter and
  saving the structured stream, for example
  `node --test --test-reporter=./attest-node-reporter.mjs --test-reporter-destination=stdout file.test.ts`,
  then replace the absolute fixtures directory in the events with
  `__FIXTURES__/`; `attest-test-fixture-lines` substitutes it back.

## Verifying in a live Emacs

The owner runs Emacs as a daemon; `emacsclient --eval` reaches it. Put
`lisp/` on `load-path` and require `attest-all`, which adds its own
subdirectories, then disable side effects:

```elisp
(progn
  (add-to-list 'load-path (expand-file-name "~/projects/attest/lisp"))
  (require 'attest-all)
  (setq attest-save-before-run nil attest-display-output nil))
```

Then in a test buffer `(attest-run-at-point)` and, after it finishes,
`(attest-run-results (attest-last-run))`, `(flymake-diagnostics)` and
the overlays with property `attest-status`. Do not call `pop-to-buffer`
inside the same form you inspect from; it changes the current buffer.

A long-lived daemon holds whatever it loaded first, so a symbol that
appears nowhere in the sources — `attest-status-mode--set-explicitly`, say,
which `define-globalized-minor-mode` used to generate — means the daemon
is running code from an older load, not that the tree is broken. Restart
it before believing a void-variable or void-function report.

## Known limits

- Rust project scope parses every `src/` and `tests/` file synchronously
  inside `:command` before cargo starts (395 ms for the 40 files of
  `stress/cargo`, cold). The run reports itself started first, so the
  wait is announced, and the parse cache makes a repeat run cheap.
- vitest reports `-t`-excluded tests as skipped; `attest-target-result-p`
  in core filters them to the run's scope. A `.only` in a file or project
  run is detected from the source, since vitest rewrites the mode during
  collection and no reporter hook can tell an excluded test from a
  `test.skip`.
- No `test.each`, `describe.each`, or computed-name handling; `stress/*/dynamic*` files track it.
- node reports nothing for tests inside `describe.skip`; discovery still lists them.
- `logs/` in this directory belongs to another tool and is not tracked.

## Next work, in rough priority

1. Chunked or child-Emacs discovery for repo-wide indexing.
2. `test.each` and parametrized names: mark positions dynamic, widen
   the name pattern.
3. Watch mode and dape integration are out of scope until the above land.
