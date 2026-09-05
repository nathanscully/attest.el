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
3. `attest.el`: the core. Everything else is a backend or a consumer of
   it.

## Layout

| path | role |
|---|---|
| `attest.el` | registry, ids, discovery + per-run position index, process runner, result cache, commands |
| `attest-node.el` + `attest-node-reporter.mjs` | node:test backend; reporter tracks nesting and emits `attest:test` events on stderr |
| `attest-vitest.el` + `attest-vitest-reporter.mjs` | vitest backend; same event shape, reuses the node query and parser; registers after node |
| `attest-rust.el` | cargo test via libtest JSON (`attest-rust-environment` sets `RUSTC_BOOTSTRAP=1`); maps names through the core index |
| `attest-pytest.el` + `attest_pytest.py` | pytest backend; plugin loaded with `-p`, JSON on stderr |
| `attest-flymake.el`, `attest-status.el`, `attest-list.el` | consumers; subscribe to hooks, read `attest--results` |
| `attest-all.el` | one entry point that requires the core, all backends and all consumers |
| `test/` | ert tests; parser tests replay `test/fixtures/*-events.jsonl`, one integration test per runner |
| `stress/` | one real project per runner (`node`, `vitest`, `cargo`, `pytest`); `test/attest-stress-test.el` runs them via `make stress` |
| `flake.nix` | dev shell and `nix flake check`; pins Emacs, grammars and runners |
| `assets/live-tlox.png` | screenshot of a live run in the daemon |
| `scratch/` | gitignored working notes (`PLAN.md`) |

## Build and test

```sh
make all          # byte-compile (warnings are errors), checkdoc, ert
make test         # ert only
make stress       # live runs against stress/; not part of make all

nix develop -c make all   # same, with the flake's pinned toolchain
nix flake check           # make all on a clean Emacs in the nix sandbox
```

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
pnpm. `nix flake check` runs `make all` in the build sandbox against
that clean Emacs, so it catches host assumptions the daemon hides.
The sandbox cannot fetch node_modules, so the vitest integration test
skips there; run the suite in the dev shell for vitest coverage.
CI (`.github/workflows/ci.yml`) runs `nix flake check` on Linux and
macOS and `make all stress` in the dev shell; setting the
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

On this machine pytest is not on PATH; `nix develop -c make all` is
the simplest fix. Outside the dev shell, run make as
`nix shell nixpkgs#python3Packages.pytest -c make ...`, prefix PATH
with a venv's bin, or point `attest-pytest-command` at a venv.

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

The owner runs Emacs as a daemon; `emacsclient --eval` reaches it. Load
the files from this directory, disable side effects, run, inspect:

```elisp
(progn
  (dolist (f '("attest" "attest-node" "attest-flymake" "attest-status" "attest-list"))
    (load (expand-file-name (concat f ".el") "~/projects/attest/") nil t))
  (setq attest-save-before-run nil attest-display-output nil))
```

Then in a test buffer `(attest-run-at-point)` and, after it finishes,
`(attest-run-results (attest-last-run))`, `(flymake-diagnostics)` and
the overlays with property `attest-status`. Do not call `pop-to-buffer`
inside the same form you inspect from; it changes the current buffer.

## Known limits

- Rust project scope parses every `src/` and `tests/` file synchronously
  before cargo starts (6.0 ms per file measured on `stress/cargo`).
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
