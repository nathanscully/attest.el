# attest.el design

Emacs 30+ test runner with pluggable per-language backends. Core uses
built-ins only and requires an Emacs built with tree-sitter. Four
backends ship: `node --test`, vitest, `cargo test` and pytest.

## Backend contract

A backend is a plist registered with `attest-register-backend`.

| key | type | purpose |
|---|---|---|
| `:predicate` | `() -> bool` | does this backend own the current buffer |
| `:project-p` | `() -> bool` | optional; does this backend own the buffer's project, test file or not. Resolves a `project` run; falls back to `:predicate` |
| `:test-file-p` | `(file) -> bool` | which project files are test files |
| `:root` | `(file) -> dir` | project root; default `project-current` |
| `:query` | `(LANG . QUERY)` or `(file) -> (LANG . QUERY)` | tree-sitter discovery query |
| `:command` | `(run) -> spec` | argv, directory, env, which stream carries results |
| `:parse-line` | `(run line) -> result(s)` | one line of the result stream to result plists |
| `:plan` | optional `(run continuation) -> nil` | asynchronous preparation; call CONTINUATION with one spec or `(:invocations SPECS)` |
| `:test-failure-exit-codes` | optional list of integers | non-zero runner exits that represent test failures |

`:command` returns `(:command ARGV :directory DIR :env ("K=V") :parse-stream stdout|stderr)`.
`:parse-line` may keep state in `(plist-get run :state)` and may call
`attest-append-output` to surface human-readable text embedded in
structured events. Core always splits stdout and stderr; the parse
stream feeds `:parse-line`, the other goes to the output buffer.
`:plan` is used when a backend must do asynchronous preparation (Cargo uses
it for metadata). It owns preparation resources and must call its
continuation exactly once unless the run is cancelled; the continuation
receives the same invocation spec shape as `:command`.
Core suppresses callbacks after cancellation, rejects a second plan launch,
and applies `attest-preparation-timeout` to preparation that is waiting on
the event loop. A timeout is a run error; backend planners should use
`attest-prepare-command` so their process and stderr pipe are cancellable.

Registration validates the backend name, plist shape, required callables and
the types of optional properties. `attest-validate-backend` and
`attest-validate-backends` expose the same checks for package and extension
tests. Backend-specific properties may be added, but core-owned properties
must keep these meanings. Invocation specs are validated before a process is
created: commands are non-empty argv lists, environments are string lists,
and the parse stream is `stdout` or `stderr`.

| backend | runner output | shipped helper | discovery |
|---|---|---|---|
| node | JSON events on stderr | `attest-node-reporter.mjs` | treesit query, JS/TS |
| vitest | JSON lines on stderr | `attest-vitest-reporter.mjs` | reuses the node query |
| rust | libtest JSON on stdout (`attest-rust-environment`) | none | treesit query, `#[test]` siblings |
| pytest | JSON lines on stderr | `attest_pytest.py` | treesit query, `test_*`/`Test*` |

Results may carry `:runner-name`, the runner's own name for the test,
which the backend uses to rerun exactly that test.

## Data model

Position (from discovery):

    (:id "FILE::ns::name" :type test|namespace :name :file :line :column
     :beg :end :parent-id)

Result (from the runner):

    (:id "CASE-ID" :definition-id "DEFINITION-ID"
     :type test|namespace :name :status
     :file :line :column :duration :message :stack :location (LINE . COL))

`:id` is the runtime-case identity. `:definition-id` points to the static
source definition when the runner provides a parameterized or execution-
target case; ordinary results use the same value for both. Consumers should
use `attest-result-case-id` and `attest-result-definition-id` rather than
splitting the plist fields themselves.

`:status` is `passed`, `failed`, `skipped` or `todo`. `:line` is the
test definition. `:location` is the failing frame inside the test file,
when the runner gives one.

Run:

    (:request ATTEST-REQUEST :backend :scope :file :root :targets :files :index
     :command :directory :process :status :result-ids :results :state
     :start-time :end-time :output-buffer)

`attest-request` captures the backend, scope, origin and resolved selection
before execution mutates the run. `attest-invocation` owns one process,
parser state, execution-target identity and terminal exit information.
Selection lists and target plists in the request are copied at the boundary,
so later run bookkeeping cannot rewrite the request a rerun or extension sees.
`attest-run-request` and the generated struct accessors are the stable read
boundary for extensions; the surrounding run plist remains internal state.

A run reports it has started before it builds its command or parses
anything, because both block: discovery reads every file in scope on the
Emacs thread, and rust indexes its crate inside `:command`.

Starting a run prunes the cache: for every file it covers, cached
results whose ids discovery no longer lists are dropped, so a deleted
or renamed test leaves no stale status. Unreadable files are skipped,
so a transient read failure never clears results, and so are files
larger than `attest-max-file-size`, where no positions means discovery
declined to look rather than the tests being gone.

`:results` maps id to the result RUN itself recorded, so
`attest-run-results` is unaffected by later runs; `attest--results`
holds only the latest result for an id, and `attest--results-by-file`
indexes those ids by the file's true name so a consumer can ask for one
file's results without walking every id. `attest-cache-result` writes
both tables for a caller that has a result outside a run, and
`attest-clear-results` forgets everything, or only one file's results
when called with a prefix argument, and fires
`attest-results-changed-functions` with the files it cleared so the
consumers redraw. `:index` maps a file's true name to
`(POSITIONS . BY-ID)`: the list in discovery order, which linking needs,
and an id-keyed table so a lookup does not scan.

`attest-run-summary` reduces a run into test counts, invocation counts,
all invocation exit codes, errors and an explicit outcome. The legacy
`:exit-code` remains the most recent invocation's code; use
`attest-run-exit-codes` when a plan ran more than one process.
`attest-run-complete-p` means preparation, execution
and result interpretation were trustworthy. Outcomes are `passed`,
`failed`, `empty`, `incomplete`, `error` or `cancelled`; lifecycle `:status`
continues to report `pending`, `running`, `finished`, `killed` or `error`.
An empty run is complete but never reported as passed.

Discovery positions are cached by canonical file, backend registration
revision, query and file modification stamp. The shared cache is bounded by
`attest-max-position-cache-entries` with least-recently-used eviction;
per-run indexes retain their own snapshot and are unaffected by eviction.
`attest-invalidate-positions` is available when a file changes without a
reliable mtime or size change.

`:scope` is `file`, `project` or `targets`. A `targets` run carries
`:targets`, a list of position plists (`:id`, `:type`, `:file`);
run-at-point passes one, rerun-failed passes the failed results, which
have the same keys. Backends build one selector per target from its
`:type`: a test matches exactly, a namespace matches every test below
it. libtest applies `--exact` globally, so cargo drops it when any
target is a namespace and may over-select.

Selectors carry names, not files, so a `targets` run covering several
files can also execute a same-named test in another of them. Node and
vitest filter what they record through `attest-target-result-p`, so an
over-selected test never reaches the cache; it still runs.

### Id scheme

`FILE::name::name…`, outermost first. Discovery and the runner build ids
independently; `attest-treesit-ids-match-runner-ids` fails if they
diverge. Node's `--test-name-pattern` matches the space-joined ancestry,
so a test id maps to `^a b c$` and a namespace to `^a b( |$)`.

The file component is a true name and every component percent-encodes
`%` and `:`, so a test literally named `a::b` cannot collide with a test
`b` nested in `a`.

An id must not depend on the scope that produced it, or one test lands
in the cache twice. libtest names are unique only within an executable,
so cargo prefixes a `@cargo/PACKAGE/KIND/NAME` component when a name
resolves in more than one of the crate's targets. That decision is taken
once per plan over every target the crate has, never over the files a
particular run happens to cover: a project run and a rerun of one of its
failures must agree.

### Nesting

Discovery: sort matches by start, nest by range containment. The query
never encodes nesting.

Runner: node emits `test:start` for a parent before its children and
`test:pass`/`test:fail` after `test:start`. The backend keeps an
`active` alist of (nesting . name) and prefixes each result with the
shallower entries.

## Data flow

    attest-run
      -> progress: start message, mode-line timer ticking every second
      -> backend :command (blocking: rust indexes the crate here)
      -> prune the cache against discovery
      -> make-process, stdout -> *attest* (ansi-color, compilation-minor-mode)
                       stderr -> line splitter -> backend :parse-line
      -> attest--record: puthash id result; run attest-result-functions
      -> sentinel: clear progress, attest-run-finished-functions,
         summary message

Consumers subscribe to four hooks and read the shared cache
`attest--results` (id -> latest result). Three report a run;
`attest-results-changed-functions` reports the cache being edited
outside one, as `attest-clear-results` does, and carries the files that
changed or nil for all of them. Core knows nothing about the consumers.
A consumer registers its hook when the feature loads, not when a buffer
mode turns on, so cache handling never depends on which buffers happen
to have the mode enabled; the minor modes own rendering alone.

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
prints one JSON event per line. `JSON.stringify` drops an
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
- A project-wide position tree. Discovery reads unopened files a run
  covers, but nothing indexes the repo ahead of a run.
- Parameterised tests (`test.each`, template-string names).
- TAP parsing.
- Concurrent runs. One run is tracked at a time: starting a run kills the
  previous one, and `attest-kill` stops whichever is current, whatever
  project it belongs to.
- Any UI that needs projectile, treemacs, transient or dash.
