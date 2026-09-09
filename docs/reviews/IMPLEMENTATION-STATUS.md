# Attest implementation status

This document records the engineering work completed during the pre-1.0
cleanup and the recommended path to a focused 1.0 release. It complements
`DESIGN.md`, which describes the current architecture, and
`IMPROVEMENT-PLAN.md`, which records the broader design rationale.

## Current position

Attest is in a strong pre-1.0 state. The core lifecycle, identity model,
backend boundary, result accounting, package layout, and runner reliability
have been substantially tightened. The four initial backends remain supported:

- Node `node --test`
- Vitest
- Cargo `cargo test`
- pytest

The project is not yet claiming a frozen 1.0 extension API. The remaining work
is primarily release hardening, documentation, compatibility testing, and a
small number of explicitly known framework limitations.

## What has been changed

### Package structure and ownership

- Moved shipped Elisp into `lisp/`, grouped into `core/`, `backends/`, and
  `consumers/`.
- Kept framework-specific reporters and plugins beside their backends.
- Added staged package creation and an installed-artifact smoke test.
- Updated the Makefile, README, Nix workflow, load paths, and package asset
  handling for the new layout.
- Kept the core and bundled backends dependency-free beyond Emacs built-ins and
  the configured external test runners.

### Backend contract

- Added validated backend registration.
- Added validation for invocation specifications and multi-invocation plans.
- Added backend registration revisions so discovery caches cannot survive a
  provider replacement accidentally.
- Isolated shared JavaScript discovery/parser behavior from Node-specific
  registration.
- Preserved the existing backend command names while making the extension
  boundary more explicit.

### Identity and model

- Added explicit accessors distinguishing runtime case IDs from static
  definition IDs.
- Preserved parameterized pytest cases and Cargo execution-target identity.
- Made IDs unambiguous for separators, percent signs, empty names, Unicode,
  and literal `::` content.
- Added `attest-request` snapshots for run intent and selection.
- Defensive-copied request file and target selections so reruns cannot mutate
  historical request data.
- Added explicit invocation records containing command, parser state, process,
  execution target, status, and exit code.

### Run lifecycle and reliability

- Made startup, process creation, stream draining, cancellation, and cleanup
  exception-safe.
- Ensured failed spawns and preparation failures finish the run without
  leaving pipes, timers, or stale process callbacks behind.
- Added `attest-run-active-p` so callbacks from cancelled or superseded runs
  cannot launch work for a replacement run.
- Added configurable preparation timeout via
  `attest-preparation-timeout` (60 seconds by default).
- Preserved sequential multi-invocation execution for Cargo and other future
  backends.
- Exposed all invocation records and exit codes in execution order while
  retaining the legacy most-recent `:exit-code` field.

### Result accounting

- Added an explicit run outcome reducer with these outcomes:
  `passed`, `failed`, `empty`, `incomplete`, `error`, and `cancelled`.
- Separated lifecycle status from test outcome.
- Added `attest-run-complete-p` and `attest-run-summary`.
- Ensured parser/protocol/infrastructure errors prevent a clean-success
  interpretation.
- Made zero-test runs explicit rather than treating them as passing.
- Preserved earlier failures when later events for the same case pass.
- Kept per-run results stable even after later runs update the global cache.

### Discovery and caching

- Preserved full-file discovery inside narrowed buffers.
- Isolated discovery cache entries by backend/provider and query.
- Added backend registration revisions to cache stamps.
- Added a bounded LRU discovery position cache controlled by
  `attest-max-position-cache-entries` (256 by default).
- Kept per-run position indexes independent from shared-cache eviction.
- Preserved explicit `attest-invalidate-positions` support for unreliable file
  timestamps or sizes.
- Added a maximum parseable file size to avoid accidental stalls on generated
  or minified files.

### Backend-specific fixes

- Cargo plans isolated invocations by package, target kind, and executable,
  reducing name collisions between binaries and integration tests.
- pytest preserves full node IDs, parameters, phases, teardown failures, and
  definition mapping.
- Node reporters preserve nesting, suffix names, file errors, and encoded IDs.
- Vitest reuses JavaScript parsing without incidental Node registration,
  detects real `.only` declarations while ignoring comments and strings, and
  filters scoped results correctly.

### Consumer and Emacs compatibility fixes

- Status/fringe markers reconcile on start, result, finish, cancellation, and
  cache clearing.
- Flymake diagnostics use explicit ownership data and preserve diagnostics
  from other backends.
- The tabulated results consumer uses stable result accessors and run-owned
  results.
- Replaced the fragile globalized status-mode implementation with an explicit
  global minor-mode lifecycle compatible with Emacs 30 and 31.
- Made status faces safe when the frame background is unspecified, avoiding
  the `unspecified-bg` startup failure.

## Verification completed

The current tree passes:

- `make all`: 138 ERT tests, byte compilation, and checkdoc.
- `make package-test`: staged installed-package smoke test.
- `make stress`: 20 expected stress results across Node, Vitest, Cargo, and
  pytest.
- `git diff --check`.

The stress suite still reports three documented expected failures for dynamic
runtime-generated names. Those are known discovery limitations, not silent
failure-loss regressions.

## Deliberately deferred

### Worker-Emacs discovery

Worker discovery remains in the long-term plan, but is not a 1.0 requirement.
The current bounded cache and measured discovery costs do not justify the
complexity yet. A worker would introduce grammar/configuration replication,
unsaved-buffer snapshots, IPC, cancellation, and worker-failure recovery.

### Other out-of-scope features

- Watch mode.
- dape integration.
- Concurrent user runs.
- Remote/TRAMP execution.
- Persisted historical databases.
- A universal runner configuration language.
- A tree UI or dependency graph.

## Recommended next steps

### 1. Freeze and document the public API

Create a concise compatibility document that identifies:

- supported interactive commands;
- supported variables and hooks;
- stable backend registration and invocation contracts;
- stable result/run accessors;
- private symbols that extensions must not depend on.

Add a minimal backend-authoring guide showing how to register a new language
without editing core. This is the most important extensibility task before
calling the API 1.0-stable.

### 2. Add the compatibility matrix

Record and test the supported combinations of:

- Emacs 30 and Emacs 31;
- Linux and macOS;
- pinned and minimum supported Node, Vitest, Cargo, and pytest versions;
- required tree-sitter grammars.

The existing Nix toolchain remains valuable, but one pinned Emacs build is not
enough to claim a two-version compatibility promise.

### 3. Finish consumer-facing incomplete-run reporting

The core now distinguishes incomplete, error, and cancelled outcomes. The
results view and output buffer should surface those states explicitly, including
run errors and preparation timeouts, instead of showing only individual test
rows.

### 4. Add a small discovery benchmark command

Measure cold and warm discovery separately, with:

- file count and total bytes;
- median and p95 time;
- cache hit/miss counts;
- consumers enabled and disabled.

Use the benchmark to decide later whether worker discovery is justified. Do
not introduce worker infrastructure before real measurements show sustained UI
stalls.

### 5. Clarify dynamic-name limitations

Document the current behavior for `test.each`, parametrized names, computed
names, and runtime-generated suites. Keep runtime results complete and honest;
where static positions are unavailable, expose that uncertainty instead of
guessing a source location.

### 6. Review the internal model before API freeze

The current result wire format remains plist-compatible, with stable accessors
on top. Before 1.0, decide whether internal result records should become
`cl-defstruct` values or remain plists behind the accessor boundary. Either
choice is viable; the important requirement is that consumers and third-party
backends do not need to split IDs or reach into mutable global tables.

### 7. Package the release candidate cleanly

Before tagging 1.0:

- move historical reviews under `docs/reviews/`;
- keep README focused on installation, usage, and supported scope;
- add release notes and a compatibility matrix;
- verify the archive contains only shipped sources, generated autoloads, and
  required reporter/plugin assets;
- run the complete suite from a clean installed artifact;
- perform a fresh daemon smoke test on Emacs 30 and Emacs 31.

## Suggested release sequence

1. Complete API/extension documentation.
2. Add compatibility and benchmark coverage.
3. Improve incomplete-run presentation in the consumers.
4. Resolve or explicitly document the dynamic-name limitations.
5. Run the release gates on both supported Emacs versions and both CI OSes.
6. Tag the first release candidate, then make only narrowly scoped fixes before
   1.0.
