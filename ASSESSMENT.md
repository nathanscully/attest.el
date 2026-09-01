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
  `neotest-run-file` produced one failed result, a flymake `:error`
  from `neotest-flymake-backend` at line 8 column 2 (the assertion, not
  the `test(` line), a red fringe dot at line 5, and the results table.
  `neotest-run-at-point` built
  `--test-name-pattern=^scan splits tokens with line numbers$`.
  Screenshot: `assets/live-tlox.png`.
- Discovery timing: 1000 synthetic files, 29 000 positions, 11.72 s
  wall, 11.7 ms per file, 0.18 s in GC (`emacs -Q --batch`, M-series Mac).

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
   process running `neotest-treesit.el` over a file list. The batch
   route is proven viable: the ert suite already parses TypeScript in
   batch with the grammar found through `treesit-extra-load-path`.
4. **The runner needs a shipped file.** The node backend depends on
   `neotest-node-reporter.mjs`. It is 15 lines and lives in the package,
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

| | neotest.el | verdict.el | test-cockpit.el |
|---|---|---|---|
| deps | none | treemacs, dash | projectile |
| core size | 504 lines + consumers of 99-129 | 1384 | 719 |
| discovery | treesit query, shared across languages | per-backend (dart uses treesit) | regexp + sexp motion |
| results UI | flymake inline, fringe, tabulated-list, compile-style output | treemacs tree | compile buffer, transient menu |
| runner scopes | test, namespace, file, project, rerun-failed | test, group, file, module, project, rerun-failed | function, module, project |
| node:test | yes | via the handoff's 90-line reference backend | no (jest only) |
| test-at-point without a UI | yes | no (tree is the UI) | yes |

What is different: results flow into flymake, the fringe and
`next-error`, which the user already has, instead of into a new tree
widget. A user can run `neotest-run-at-point` with no consumer loaded
and get compile-style output. That is the reason another package is
justified, and it is the only reason. If flymake had not worked, the
right move would have been a node backend for verdict.

## Risks

- The name `neotest` collides with the Neovim project. Rename before
  publishing or accept the confusion.
- `flymake-list-only-diagnostics` is a variable other tools may also
  set; entries are keyed by file, so collisions are unlikely but possible.
- Node's event ordering (`test:complete` before `test:start`) is odd
  and undocumented; the parser relies only on `test:start` preceding
  `test:pass`/`test:fail`, which held on v22.23.2.

## Next

- Phase 3: a pytest backend. If it needs a change to core, the contract
  was wrong.
- Chunked discovery over `project-files` behind an idle timer, with the
  timing above as the budget.
- `test.each` and template-string names: mark positions dynamic and
  widen the name pattern, as neotest-nodejs does.
