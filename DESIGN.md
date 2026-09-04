# attest.el design

Emacs 30+ test runner with pluggable per-language backends. Core uses
built-ins only and requires an Emacs built with tree-sitter. Four
backends ship: `node --test`, vitest, `cargo test` and pytest.

## Backend contract

A backend is a plist registered with `attest-register-backend`.

| key | type | purpose |
|---|---|---|
| `:predicate` | `() -> bool` | does this backend own the current buffer |
| `:test-file-p` | `(file) -> bool` | which project files are test files |
| `:root` | `(file) -> dir` | project root; default `project-current` |
| `:query` | `(LANG . QUERY)` or `(file) -> (LANG . QUERY)` | tree-sitter discovery query |
| `:command` | `(run) -> spec` | argv, directory, env, which stream carries results |
| `:parse-line` | `(run line) -> result(s)` | one line of the result stream to result plists |

`:command` returns `(:command ARGV :directory DIR :env ("K=V") :parse-stream stdout|stderr)`.
`:parse-line` may keep state in `(plist-get run :state)` and may call
`attest-append-output` to surface human-readable text embedded in
structured events. Core always splits stdout and stderr; the parse
stream feeds `:parse-line`, the other goes to the output buffer.

| backend | lines | runner output | shipped helper | discovery |
|---|---|---|---|---|
| node | 239 | JSON events on stderr | `attest-node-reporter.mjs` (19 lines) | treesit query, JS/TS |
| vitest | 165 | JSON lines on stderr | `attest-vitest-reporter.mjs` (22 lines) | reuses the node query |
| rust | 176 | libtest JSON on stdout (`RUSTC_BOOTSTRAP=1`) | none | treesit query, `#[test]` siblings |
| pytest | 146 | JSON lines on stderr | `attest_pytest.py` (42 lines) | treesit query, `test_*`/`Test*` |

Results may carry `:runner-name`, the runner's own name for the test,
which the backend uses to rerun exactly that test.

## Data model

Position (from discovery):

    (:id "FILE::ns::name" :type test|namespace :name :file :line :column
     :beg :end :parent-id)

Result (from the runner):

    (:id "FILE::ns::name" :type test|namespace :name :status
     :file :line :column :duration :message :stack :location (LINE . COL))

`:status` is `passed`, `failed`, `skipped` or `todo`. `:line` is the
test definition. `:location` is the failing frame inside the test file,
when the runner gives one.

Run:

    (:backend :scope :file :root :targets :files :index :position-index
     :command :directory :process :status :result-ids :results :state
     :start-time :end-time :output-buffer)

`:results` maps id to the result RUN itself recorded, so
`attest-run-results` is unaffected by later runs; `attest--results`
holds only the latest result for an id. `:position-index` maps a file
to an id-keyed table of its positions.

`:scope` is `file`, `project` or `targets`. A `targets` run carries
`:targets`, a list of position plists (`:id`, `:type`, `:file`);
run-at-point passes one, rerun-failed passes the failed results, which
have the same keys. Backends build one selector per target from its
`:type`: a test matches exactly, a namespace matches every test below
it. libtest applies `--exact` globally, so cargo drops it when any
target is a namespace and may over-select.

### Id scheme

`FILE::name::name…`, outermost first. Discovery and the runner build ids
independently; `attest-treesit-ids-match-runner-ids` fails if they
diverge. Node's `--test-name-pattern` matches the space-joined ancestry,
so a test id maps to `^a b c$` and a namespace to `^a b( |$)`.

### Nesting

Discovery: sort matches by start, nest by range containment. The query
never encodes nesting.

Runner: node emits `test:start` for a parent before its children and
`test:pass`/`test:fail` after `test:start`. The backend keeps an
`active` alist of (nesting . name) and prefixes each result with the
shallower entries.

## Data flow

    attest-run
      -> backend :command
      -> progress: start message, mode-line timer ticking every second
      -> make-process, stdout -> *attest* (ansi-color, compilation-minor-mode)
                       stderr -> line splitter -> backend :parse-line
      -> attest--record: puthash id result; run attest-result-functions
      -> sentinel: clear progress, attest-run-finished-functions,
         summary message

Consumers subscribe to three hooks and read the shared cache
`attest--results` (id -> latest result). Core knows nothing about them.

## Built-in per feature

| feature | built-in | file |
|---|---|---|
| run process, stream two outputs | `make-process` with `:stderr` pipe process | attest.el |
| raw output with file:line jumps | `compilation-minor-mode`, one extra `compilation-error-regexp-alist` entry for `file://` URLs | attest.el |
| test discovery | `treesit-query-capture`; names paired with their innermost definition capture, so Emacs 30 works | attest.el |
| inline failures | `flymake-diagnostic-functions`, `flymake-make-diagnostic` | attest-flymake.el |
| failures in unvisited files | `flymake-list-only-diagnostics` (read by `flymake-show-project-diagnostics`) | attest-flymake.el |
| gutter status | `define-fringe-bitmap` + overlay `before-string` | attest-status.el |
| results table | `tabulated-list-mode` | attest-list.el |
| project files | `project-files` filtered by `:test-file-p` | attest.el |
| tests | `ert` on recorded fixtures | test/ |

### flymake specifics

Flymake calls a backend and hands it a token; reports with an old token
signal `flymake-error`. So test results are not pushed through a saved
report function. Instead the backend answers from the cache whenever
flymake asks, and `attest-flymake--refresh` calls `(flymake-start nil t)`
in each touched buffer after a run. That reruns every backend in the
buffer, which is cheap for lsp-mode and eglot because they also answer
from a cache.

Disabling the mode removes the backend from
`flymake-diagnostic-functions` and reruns `flymake-start`, which
clears state for backends no longer listed.

## Runner output format

TAP was rejected. The `# Subtest:` line names a node before its result
line, YAML blocks carry the error, and columns are lost. Node's reporter
API gives structured events instead, so `attest-node-reporter.mjs`
(15 lines) prints one JSON event per line. `JSON.stringify` drops an
Error's `message` and `stack`, so the reporter copies those fields
explicitly. Both reporters run in one process:

    node --test --test-reporter=spec --test-reporter-destination=stdout \
                --test-reporter=attest-node-reporter.mjs --test-reporter-destination=stderr \
                [--test-name-pattern=...] files...

## What the second, third and fourth backends changed in core

- Tree-sitter became a hard requirement and discovery moved from
  `attest-treesit.el` into core, with a per-run position index. The
  rust backend's private index and the `:positions` escape hatch went
  away with it.

- Always create the stderr pipe, so a backend parsing stdout (cargo)
  still gets its stderr into the output buffer.
- `attest-append-output` became public: libtest embeds the failure
  text in the JSON event, and vitest and node print errors as plain
  lines on the parse stream.
- Any normal exit counts as `finished`; cargo exits 101 on failure.
- `attest--parse-line` catches backend errors and drops the line.
- A failed spawn finishes the run with `error` instead of leaving it
  `running`.
- `attest-results-for-file` tolerates results without a file.

None of these touched the backend contract or the consumers.

## Not building

- A tree view. `attest-list` is a flat table; failures-only filter covers the common case.
- Watch mode and the LSP-derived dependency graph.
- Debugging (dape) integration.
- Discovery in unopened files and a project-wide position tree.
- Parameterised tests (`test.each`, template-string names).
- TAP parsing.
- A second backend. Phase 3 decides whether the contract survives pytest or cargo.
- Any UI that needs projectile, treemacs, transient or dash.
