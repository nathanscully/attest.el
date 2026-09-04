# Assessment: does the built-ins thesis hold?

Yes for phases 1 and 2. The prototype runs test-at-point, file and
project scopes, streams results, marks the fringe, publishes failures
through flymake and lists them in `tabulated-list-mode`. It loads with
`emacs -Q` and requires nothing outside Emacs 31.1.

## Evidence

- `make all`: byte-compile with `byte-compile-error-on-warn`, checkdoc
  clean, 21 ert tests passing (2026-09-01).
- 20 tests parse recorded fixtures. One spawns `node --test` on
  `test/fixtures/demo.test.ts`, waits for the sentinel and checks nine
  streamed results and the failing frame `(10 . 5)`.
- Live in the user's Emacs daemon on `tlox/src/scanner.test.ts`:
  `attest-run-file` produced one failed result, a flymake `:error`
  from `attest-flymake-backend` at line 8 column 2 (the assertion, not
  the `test(` line), a red fringe dot at line 5, and the results table.
  `attest-run-at-point` built
  `--test-name-pattern=^scan splits tokens with line numbers$`.
  Screenshot: `assets/live-tlox.png`.
- Discovery timing: 1000 synthetic files, 29 000 positions, 11.72 s
  wall, 11.7 ms per file, 0.18 s in GC (`emacs -Q --batch`, M-series Mac).

## Phase 3: the abstraction under three more backends

vitest, `cargo test` and pytest were added after the contract was fixed.
Each is one file plus, for the JS and Python runners, a small reporter
or plugin. The contract did not change; core changed in six small ways
listed in DESIGN.md, all robustness, none visible to backends or
consumers. 40 ert tests pass, including one live run per runner.

What each backend taught:

- **vitest** reuses the node discovery query unchanged. `-t` matches
  the space-joined ancestry like node. vitest reports tests excluded by
  `-t` as `skipped`, so the backend filters results to the run's scope
  or a targeted run would grey out every other test. Backend
  ordering matters: vitest registers after node and only claims buffers
  whose package has `node_modules/.bin/vitest`.
- **rust** is the hard case. libtest names tests by module path and
  never mentions files or lines, so the backend discovers positions in
  the run's files first and resolves events against them. This is the
  position-index idea from phase 4 arriving early, kept inside the
  backend. The JSON stream is behind `-Z unstable-options`, which
  stable rustc accepts with `RUSTC_BOOTSTRAP=1`; the text format would
  need a stateful parser instead. Project scope parses every file
  under `src/` and `tests/` synchronously (11.7 ms each).
- **pytest** node ids already have the id shape. The plugin emits
  `rootdir` so paths resolve on any machine. Decorated tests report the
  decorator line and discovery reports the `def` line; since core now
  takes the line from the position, the marker lands on the `def`.
  Skips surface in the `setup` phase.

Live in the daemon: vitest `attest-run-at-point` on
`poly/packages/core/src/dispatch.test.ts` ran one test in
`packages/core` with `-t "^dispatch loop runs handlers …$"`; cargo on the
fixture crate placed the flymake error at `src/lib.rs:19:9`; pytest on
the fixture placed it at the `raise` line.

## Decision: tree-sitter is required

Taken on 1 September 2026 after the three extra backends. Evidence that
Emacs is moving this way, from the NEWS files of the installed 31.1:
`treesit-enabled-modes` turns every ts-mode on with one setting (26
languages in the bundled remap table); `treesit-auto-install-grammar`
defaults to `ask`, so a missing grammar becomes a prompt to build it;
loading a ts-mode remaps the classic mode (Emacs 30); new built-in
modes (Elixir, HEEx, Lua, PHP, `treesit-x`) have no classic version.
The qualifier: `treesit-enabled-modes` still defaults to `nil`, and
auto-install needs a C compiler and git.

What it bought: `:positions` and `attest-treesit.el` are gone, core
indexes positions per run and fills `:line`, `:column` and `:type` on
every result, the rust backend lost 24 lines and its private index,
and pytest's decorator-line drift disappeared because the position
wins over the runner's line. Cost: the package does nothing on an
Emacs without tree-sitter or without the grammar for the language, and
project scope for rust still parses every file synchronously before the
run.

## Where it breaks down

1. **Flymake is pull, not push.** A backend cannot report at will; a
   report with a stale token errors. The workaround is to answer from a
   cache and call `flymake-start` after each run. It works and costs one
   extra round of the other backends per touched buffer. It also means
   results appear only in buffers with `flymake-mode` on.
2. **Unvisited files are second class.** `flymake-list-only-diagnostics`
   is documented as "temporary stand-ins" and is never highlighted; it
   only feeds `flymake-show-project-diagnostics`. Good enough for a
   project-wide failure list, not for anything richer.
3. **Discovery of unopened files blocks Emacs.** 11.7 ms per file means
   a 1000-file repo freezes for 12 s if parsed synchronously. Two
   built-in ways out, neither built here: an idle timer parsing one file
   per tick (each tick under a frame), or `emacs -Q --batch` as a child
   process running `attest-treesit.el` over a file list. The batch
   route is proven viable: the ert suite already parses TypeScript in
   batch with the grammar found through `treesit-extra-load-path`.
4. **The runner needs a shipped file.** The node backend depends on
   `attest-node-reporter.mjs`. It is 15 lines and lives in the package,
   but it is a file on disk the backend must locate with `load-file-name`.
5. **`compilation-minor-mode` needed help.** Node prints frames as
   `file:///abs/path.ts:21:9`; no default rule matches the URL form, so
   core adds one regexp.
6. **Column conventions differ.** Node reports 1-based columns,
   tree-sitter 0-based. Positions normalise to 1-based; consumers must
   remember `flymake-diag-region` takes a 1-based column.

None of these forced a third-party dependency.

## Open questions from the brief

1. *Does flymake work for test failures?* Yes, with the pull model above.
   Inline display, buffer list and project list all work.
2. *TAP or something else?* A custom reporter emitting JSON lines. TAP
   loses columns and reports a name before its result; the reporter API
   gives file, line, column, nesting, skip/todo flags and the error
   object.
3. *Discovery without opening?* In-process is 11.7 ms per file. Fine
   for the open buffer, not for a repo. Chunk it or run it in a batch
   Emacs.
4. *Reuse verdict's contract?* No. Verdict's four functions
   (predicate, context, command, line-handler) map onto this contract,
   and its `verdict-event` protocol resembles `:parse-line` returning
   results. But verdict's value is its treemacs UI, and that UI is the
   dependency this design exists to avoid. A node backend could be
   contributed to verdict separately; the flymake and fringe consumers
   cannot.

## Comparison

| | attest.el | verdict.el | test-cockpit.el |
|---|---|---|---|
| deps | none | treemacs, dash | projectile |
| core size | one core file plus one file per backend and per consumer | 1384 lines | 719 lines |
| discovery | treesit query, shared across languages | per-backend (dart uses treesit) | regexp + sexp motion |
| results UI | flymake inline, fringe, tabulated-list, compile-style output | treemacs tree | compile buffer, transient menu |
| runner scopes | test, namespace, file, project, rerun-failed | test, group, file, module, project, rerun-failed | function, module, project |
| runners | node:test, vitest, cargo, pytest | dart, buttercup | cargo, cask, mix, jest, python |
| test-at-point without a UI | yes | no (tree is the UI) | yes |

What is different: results flow into flymake, the fringe and
`next-error`, which the user already has, instead of into a new tree
widget. A user can run `attest-run-at-point` with no consumer loaded
and get compile-style output. That is the reason another package is
justified, and it is the only reason. If flymake had not worked, the
right move would have been a node backend for verdict.

## Risks

- Renamed from neotest (September 2026) to avoid colliding with the
  Neovim project of that name.
- `flymake-list-only-diagnostics` is a variable other tools may also
  set; entries are keyed by file, so collisions are unlikely but possible.
- Node's event ordering (`test:complete` before `test:start`) is odd
  and undocumented; the parser relies only on `test:start` preceding
  `test:pass`/`test:fail`, which held on v22.23.2.

## Next

- Chunked discovery over `project-files` behind an idle timer, with the
  timing above as the budget.
- `test.each` and template-string names: mark positions dynamic and
  widen the name pattern, as attest-nodejs does.
