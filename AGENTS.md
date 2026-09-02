# neotest.el

Emacs test runner with per-language backends. Core is built-ins only and
requires an Emacs built with tree-sitter. Four backends: `node --test`,
vitest, `cargo test`, pytest. Three consumers: flymake, fringe status,
tabulated results list.

Read in this order before changing anything:

1. `DESIGN.md`: backend contract, data model, run lifecycle, which
   built-in provides each feature, what is deliberately not built.
2. `ASSESSMENT.md`: what works, where the built-ins thesis strains,
   the tree-sitter decision, comparison with verdict and test-cockpit.
3. `neotest.el`: the core, 685 lines. Everything else is a backend or a
   consumer of it.

## Layout

| path | role |
|---|---|
| `neotest.el` | registry, ids, discovery + per-run position index, process runner, result cache, commands |
| `neotest-node.el` + `neotest-node-reporter.mjs` | node:test backend; reporter tracks nesting and emits `neotest:test` events on stderr |
| `neotest-vitest.el` + `neotest-vitest-reporter.mjs` | vitest backend; same event shape, reuses the node query and parser; registers after node |
| `neotest-rust.el` | cargo test via libtest JSON (`RUSTC_BOOTSTRAP=1`); maps names through the core index |
| `neotest-pytest.el` + `neotest_pytest.py` | pytest backend; plugin loaded with `-p`, JSON on stderr |
| `neotest-flymake.el`, `neotest-status.el`, `neotest-list.el` | consumers; subscribe to hooks, read `neotest--results` |
| `test/` | ert tests; parser tests replay `test/fixtures/*-events.jsonl`, one integration test per runner |
| `stress/` | one real project per runner (`node`, `vitest`, `cargo`, `pytest`); `test/neotest-stress-test.el` runs them via `make stress` |
| `assets/live-tlox.png` | screenshot of a live run in the daemon |
| `scratch/` | gitignored working notes (`PLAN.md`) |

## Build and test

```sh
make all          # byte-compile (warnings are errors), checkdoc, ert
make test         # ert only
make stress       # live runs against stress/; not part of make all
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

Requirements on the machine:

- Emacs 30+ with tree-sitter. Grammars for `typescript`, `tsx`,
  `javascript`, `rust`, `python`. Set `EMACS_TREE_SITTER_GRAMMARS` to
  the directory holding `libtree-sitter-*.dylib` if Emacs does not find
  them; `test/test-helper.el` reads it.
- node (integration test), cargo (integration test; first run compiles
  `test/fixtures/rs`), pytest on PATH (integration test; skipped if
  absent), `pnpm install` in `test/fixtures/vitest` for the vitest
  integration test (skipped if `node_modules/.bin/vitest` is absent).

On this machine pytest is not on PATH. Run `make all` and `make stress`
as `nix shell nixpkgs#python3Packages.pytest -c make ...`, prefix PATH
with a venv's bin, or point `neotest-pytest-command` at a venv.

If `NODE_OPTIONS` is set in your shell it can break `node --test`;
use `env -u NODE_OPTIONS node ...` when testing by hand.

## Conventions

- `lexical-binding: t`, prefix `neotest-`, private names `neotest--`.
- No inline comments; docstrings on every definition; checkdoc clean.
- No third-party dependencies in core or backends. Built-ins only.
- Backends never report where a test is. Core fills `:line`, `:column`
  and `:type` from the discovered position in `neotest--record`.
- Ids are `FILE::name::name`. Discovery and the runner must agree; every
  backend has a test asserting the id sets match.
- Run scopes are `file`, `project` and `targets`. Run-at-point and
  rerun-failed are both `targets` runs; backends build one selector per
  target from its `:type`.
- Consumers subscribe to the abnormal hooks `neotest-run-started-functions`,
  `neotest-result-functions` and `neotest-run-finished-functions`.
- Parser tests run on recorded fixtures, never on a live process. Keep
  one integration test per runner that spawns the real thing and
  `skip-unless` it is installed.
- Record a fixture by running the runner with the bundled reporter and
  saving the structured stream, for example
  `node --test --test-reporter=./neotest-node-reporter.mjs --test-reporter-destination=stdout file.test.ts`.

## Verifying in a live Emacs

The owner runs Emacs as a daemon; `emacsclient --eval` reaches it. Load
the files from this directory, disable side effects, run, inspect:

```elisp
(progn
  (dolist (f '("neotest" "neotest-node" "neotest-flymake" "neotest-status" "neotest-list"))
    (load (expand-file-name (concat f ".el") "~/projects/emacs-neotest/") nil t))
  (setq neotest-save-before-run nil neotest-display-output nil))
```

Then in a test buffer `(neotest-run-at-point)` and, after it finishes,
`(neotest-run-results (neotest-last-run))`, `(flymake-diagnostics)` and
the overlays with property `neotest-status`. Do not call `pop-to-buffer`
inside the same form you inspect from; it changes the current buffer.

## Known limits

- Rust project scope parses every `src/` and `tests/` file synchronously
  before cargo starts (6.0 ms per file measured on `stress/cargo`).
- vitest reports `-t`-excluded tests as skipped; `neotest-vitest--wanted-p`
  filters them to the run's scope.
- No `test.each`, `describe.each`, or computed-name handling; `stress/*/dynamic*` files track it.
- node reports nothing for tests inside `describe.skip`; discovery still lists them.
- The name collides with Neovim's neotest; rename before publishing.
- `logs/` in this directory belongs to another tool and is not tracked.

## Next work, in rough priority

1. Chunked or child-Emacs discovery for repo-wide indexing.
2. `test.each` and parametrized names: mark positions dynamic, widen
   the name pattern.
3. Watch mode and dape integration are out of scope until the above land.
