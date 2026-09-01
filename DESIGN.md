# neotest.el design

Emacs 30+ test runner with pluggable per-language backends. Core uses
built-ins only. One backend ships: Node's `node --test`.

## Backend contract

A backend is a plist registered with `neotest-register-backend`.

| key | type | purpose |
|---|---|---|
| `:predicate` | mode symbol, regexp, or thunk | does this backend own the current buffer |
| `:test-file-p` | `(file) -> bool` | which project files are test files |
| `:root` | `(file) -> dir` | project root; default `project-current` |
| `:query` | `(LANG . QUERY)` or thunk | tree-sitter discovery query |
| `:positions` | `(buffer) -> positions` | discovery without tree-sitter |
| `:command` | `(run) -> spec` | argv, directory, env, which stream carries results |
| `:parse-line` | `(run line) -> result(s)` | one line of the result stream to result plists |

`:command` returns `(:command ARGV :directory DIR :env ("K=V") :parse-stream stdout|stderr)`.
`:parse-line` may keep state in `(plist-get run :state)`.

The node backend is 236 lines. It adds `:root` (nearest `package.json`)
and `:parse-stream stderr`.

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

    (:backend :scope :file :root :position :positions :files :results
     :command :directory :process :status :result-ids :state
     :start-time :end-time :output-buffer)

`:scope` is `test`, `namespace`, `file`, `project` or `results`
(rerun-failed).

### Id scheme

`FILE::name::name…`, outermost first. Discovery and the runner build ids
independently; `neotest-treesit-ids-match-runner-ids` fails if they
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

    neotest-run
      -> backend :command
      -> make-process, stdout -> *neotest* (ansi-color, compilation-minor-mode)
                       stderr -> line splitter -> backend :parse-line
      -> neotest--record: puthash id result; run neotest-result-hook
      -> sentinel: neotest-run-finished-hook, summary message

Consumers subscribe to three hooks and read the shared cache
`neotest--results` (id -> latest result). Core knows nothing about them.

## Built-in per feature

| feature | built-in | file |
|---|---|---|
| run process, stream two outputs | `make-process` with `:stderr` pipe process | neotest.el |
| raw output with file:line jumps | `compilation-minor-mode`, one extra `compilation-error-regexp-alist` entry for `file://` URLs | neotest.el |
| test discovery | `treesit-query-capture` with `GROUPED` | neotest-treesit.el |
| inline failures | `flymake-diagnostic-functions`, `flymake-make-diagnostic` | neotest-flymake.el |
| failures in unvisited files | `flymake-list-only-diagnostics` (read by `flymake-show-project-diagnostics`) | neotest-flymake.el |
| gutter status | `define-fringe-bitmap` + overlay `before-string` | neotest-status.el |
| results table | `tabulated-list-mode` | neotest-list.el |
| project files | `project-files` filtered by `:test-file-p` | neotest.el |
| tests | `ert` on recorded fixtures | test/ |

### flymake specifics

Flymake calls a backend and hands it a token; reports with an old token
signal `flymake-error`. So test results are not pushed through a saved
report function. Instead the backend answers from the cache whenever
flymake asks, and `neotest-flymake--refresh` calls `(flymake-start nil t)`
in each touched buffer after a run. That reruns every backend in the
buffer, which is cheap for lsp-mode and eglot because they also answer
from a cache.

Disabling the mode removes the backend from
`flymake-diagnostic-functions` and reruns `flymake-start`, which
clears state for backends no longer listed.

## Runner output format

TAP was rejected. The `# Subtest:` line names a node before its result
line, YAML blocks carry the error, and columns are lost. Node's reporter
API gives structured events instead, so `neotest-node-reporter.mjs`
(15 lines) prints one JSON event per line. `JSON.stringify` drops an
Error's `message` and `stack`, so the reporter copies those fields
explicitly. Both reporters run in one process:

    node --test --test-reporter=spec --test-reporter-destination=stdout \
                --test-reporter=neotest-node-reporter.mjs --test-reporter-destination=stderr \
                [--test-name-pattern=...] files...

## Not building

- A tree view. `neotest-list` is a flat table; failures-only filter covers the common case.
- Watch mode and the LSP-derived dependency graph.
- Debugging (dape) integration.
- Discovery in unopened files and a project-wide position tree.
- Parameterised tests (`test.each`, template-string names).
- TAP parsing.
- A second backend. Phase 3 decides whether the contract survives pytest or cargo.
- Any UI that needs projectile, treemacs, transient or dash.
