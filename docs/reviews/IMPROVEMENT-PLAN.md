# Attest: improvement plan toward 1.0

Status: proposed implementation plan, based on REVIEW-3.md and the current
library. This document describes intended changes; it does not claim they
are implemented. CONTEXT.md defines the proposed vocabulary.

Implementation note: the containment fixes and `lisp/` package layout are
now in the tree, including the isolated package smoke test. The first part
of M4 is also landed: backend registration and invocation specs have a
validated boundary, and the four bundled backends pass the shared contract
tests. M3 has started with explicit case/definition result accessors and
invocation state fields while retaining plist compatibility. The run outcome
reducer now distinguishes clean pass, test failure, empty, incomplete,
infrastructure error and cancellation. Cancellable discovery and the
remaining protocol work are still future milestones. Preparation now has a
bounded timeout and stale asynchronous callbacks cannot launch a cancelled
run. Multi-invocation runs now retain execution-order invocation records and
all exit codes instead of exposing only the last process. Discovery now has a
bounded LRU cache and backend registration revisions in its cache key.

## Direction

Build a small testing engine with framework backends and independent
Emacs consumers. Keep built-in dependencies, usable commands without a UI,
and the current Flymake/fringe/results integrations. Make the engine safe
for unfamiliar frameworks and large projects before expanding the UI.

Take advantage of the unpublished status: change the ID format and backend
contract now. Do not maintain two internal models or preserve accidental
plist behavior for compatibility. Retain useful interactive command names.
Move files in a separate step from behavioral changes so regressions remain
easy to locate.

Success means reliable accounting of every reported failure, explicit
handling of incomplete execution, responsive preparation and cancellation,
and a backend that can be contributed without modifying core.

## 1. Proposed repository layout

```text
attest/
  README.md
  DESIGN.md
  CONTEXT.md
  CONTRIBUTING.md
  IMPROVEMENT-PLAN.md
  Makefile
  flake.nix
  lisp/
    attest.el                     public commands and orchestration entry point
    attest-all.el                 optional bundled setup
    core/
      attest-model.el             records, identity, validation
      attest-backend.el           registry, detection, configuration
      attest-discovery.el         snapshots, caches, preparation scheduling
      attest-treesit.el           shared tree-sitter discovery implementation
      attest-process.el          spawning, framing, draining, resource cleanup
      attest-run.el              run lifecycle, invocations, cancellation
      attest-results.el          result reduction, aggregation, cache, events
    backends/
      shared/
        attest-javascript.el     shared JS discovery and selectors
      node/
        attest-node.el
        attest-node-reporter.mjs
      vitest/
        attest-vitest.el
        attest-vitest-reporter.mjs
      cargo/
        attest-rust.el
      pytest/
        attest-pytest.el
        attest_pytest.py
    consumers/
      attest-flymake.el
      attest-status.el
      attest-list.el
  test/
    core/
    backends/
    consumers/
    contract/
    integration/
    fixtures/
    test-helper.el
  stress/                         existing committed runner projects
  bench/                          repeatable performance harness
  docs/
    backend-authoring.md
    consumer-authoring.md
    compatibility.md
    releases.md
    reviews/                      historical assessments/review responses
  assets/
  build/                          ignored package staging/output
```

Group by framework rather than language: Node and Vitest have different
execution behavior despite sharing discovery. Keep reporter/plugin assets
beside their backend. Keep existing feature names such as `attest-rust`;
renaming files and public symbols is not needed merely to call the folder
`cargo`.

Extract JS helpers so loading Vitest does not register Node as an incidental
side effect. Avoid a miscellaneous `utils.el`: a helper belongs to the
module that owns its meaning. Do not split each operation into a new file;
the modules above represent independently testable responsibilities.

Emacs packaging is part of this move, not a follow-up. Define explicit
development load paths and source manifests in the build. Stage the shipped
Elisp and uniquely named reporter assets together in a flat package directory,
so ordinary package loading does not require recursive `load-path` mutation.
Resolve assets beside the loaded backend in both development and the staged
package. Exclude fixtures, tests, node_modules, scratch files and review docs.

Generate autoloads from the intended package sources. Test byte compilation
and installation from the staged artifact in a cold Emacs with no checkout
on `load-path`; exercise reporter discovery there. Update Makefile, Nix,
CI and contributor commands in the same layout change. Verify archive
contents explicitly and fail on duplicate flattened names.

## 2. Dependency and ownership rules

| Module | Owns | Must not own |
|---|---|---|
| Model | Value types, canonical identity, invariants | Processes, UI, framework heuristics |
| Backend registry | Registration, detection, explicit overrides | Running tests during detection |
| Discovery | Snapshot lifetime, cache, scheduling | Interpreting runtime outcomes |
| Tree-sitter helper | Capture pairing, ranges, syntax traversal | Universal JS/Python string decoding |
| Process | Transport and process resources | Meaning of runner exit codes |
| Run | Preparation, invocation scheduling, terminal state | UI rendering or framework name guessing |
| Results | Per-run records, latest cache, aggregation, event delivery | Source parsing or spawning |
| Backend | Framework discovery rules, selection, protocol semantics | Writing core caches or calling consumers |
| Consumer | Presentation and navigation | Mutating results or determining success |

Keep the dependency graph acyclic: low-level model/transport code must not
require the public command facade. Backends depend on the public backend
contract and shared discovery facilities. Consumers depend on public read
APIs and notifications. No consumer reads `attest--results` directly.

Prefer explicit arguments over ambient current-buffer state. Capture the
origin buffer, directory and resolved settings before asynchronous work;
timers must never consult whichever buffer happens to be current later.

## 3. Replace the implicit data contract

Use `cl-defstruct` for internal mutable run/invocation state and important
records, with constructors and accessors. This makes fields, ownership and
reset behavior explicit. Registration can remain a validated keyword API.
Avoid exposing mutable internal structs as a compatibility promise; offer
documented read accessors and immutable-by-contract snapshots to extensions.

### Identity and selection

- Store raw name segments explicitly. IDs are opaque, unambiguously encoded
  keys, never an input to name-pattern construction.
- Namespace identity by backend, canonical file and execution context where
  applicable. Preserve the user's path spelling separately for display.
- Distinguish a definition ID from a runtime case ID. A case links to a
  definition when that relationship is known; unknown cases are valid results.
- Preserve a backend's raw runtime identity and rerun selector, including
  full pytest nodeids and Cargo target identity.
- Names containing `::`, spaces, escapes and Unicode must round-trip without
  changing selectors. Decode source literals using language-specific logic.
- Repeated sibling names need a backend-supported discriminator. An occurrence
  number is safe only when the runner provides enough evidence to map it.
  Ambiguous cases remain distinct run-local records with a stated rerun
  limitation; never guess a source location or collapse failures.
- Canonicalize paths once at boundaries and memoize within a run. Scope
  membership and lookup use the same identity rules. Aliases require actual
  file equivalence or an explicit backend mapping.
- A selector advertises whether execution is exact or may include additional
  tests. Filtering recorded results does not undo those tests' side effects.
  Prefer per-file/per-target invocations when these remove over-selection.

Acceptance examples: a literal `a::b` differs from suite `a` / test `b`;
two Cargo executables can both contain `same`; two pytest parameters remain
separate; an unrelated file's identically named test supplies no location.

### Run request, run and invocation

A request contains backend, root, selection and resolved execution settings.
A run is a fresh attempt with its own preparation work, discovery snapshot,
invocations, results, errors and resources. An invocation owns one command,
execution-target identity, streams, parser state and exit information.

`rerun-last` creates a new run from the previous request and refreshes source
discovery and executable planning. `rerun-failed` creates a request from the
previous run's failed runtime selectors. Neither copies transient fields.
Document whether settings are reused: recommend preserving the previous
resolved runner settings for rerun, with a fresh normal command picking up
changed configuration. Always recheck executable availability and source.

### Outcome and completeness

Represent lifecycle (`preparing`, `running`, `draining`, terminal) separately
from test outcome and completeness. Terminal reason is completed, cancelled
or error; a completed run may contain failed tests.

Preserve exit code/signal and structured run errors. A clean success requires
successful preparation, backend-validated completion and a trustworthy stream,
with no failed cases. Zero tests is an explicit outcome, not proof that a
selection was valid. Unsupported or unmapped discovery does not hide runtime
results; incomplete collection and malformed result events prevent a clean
success indication.

Keep each case's phase/attempt information where a framework needs it.
Within one attempt, later passing events cannot erase an earlier failure.
Retries are different attempts: retain their history and expose retry/flaky
semantics explicitly rather than confusing retries with teardown updates.
Define deterministic parent aggregation and count runtime cases in summaries.
The results list may expand cases; fringe markers summarize their definition.

## 4. Define a small, explicit backend protocol

Publish version 1 of the extension contract only after migrating all four
backends. The following responsibilities are proposed; settle exact Elisp
signatures during the model milestone rather than freezing these labels now.

| Operation | Responsibility |
|---|---|
| Detect | Cheap ownership decision using a supplied context |
| Resolve root | Framework/package execution boundary |
| Discover | Definitions and completeness for a source snapshot |
| Prepare/plan | Execution targets and invocation specs for a selection |
| Parse | Transport lines to validated case, error and completion events |
| Finalize | Combine stream state and process exit into invocation outcome |

Detection must support an explicit backend override. Offer deliberate local
configuration for mixed-framework projects and globally installed/custom
runner commands. Do not use registration order as the only public way to
choose a backend. Loading a backend should register it without filesystem
scans or launching its executable.

Preparation can require external discovery such as Cargo metadata. Give it
cancellable tasks using core's transport facilities; do not block the UI
with `process-lines` or hide a project parse inside a command constructor.
Execution plans may contain several invocations. Start with sequential
invocations; concurrency within a run is a later measured optimization.
Retain the current one-active-user-run policy for 1.0.

Provide the tree-sitter discoverer as the default implementation. Allow a
backend to normalize captures or supply runner-assisted discovery through
the same snapshot contract. This is a controlled extension point with
validation, not permission to mutate core internals.

Recommendation: move tree-sitter availability checks from core load into
the tree-sitter discovery provider. The shipped static discovery still needs
the appropriate grammars, but transport/results/consumers and future
collector-backed frameworks need not. This intentionally revises the current
hard-requirement decision; document that trade-off before implementing it.

Validate registration and invocation specs once at their boundaries. Report
the backend name and invalid field. Use built-in validation, not a new schema
dependency. Keep mutable backend state scoped to its preparation or invocation.

## 5. Make the lifecycle exception-safe

1. Validate the request and capture execution context.
2. Register a preparing run and announce it before expensive work.
3. Save as configured, collect versioned discovery and build a plan.
4. Notify selection/pending-state consumers from the resolved plan.
5. Execute invocations, record all valid events and retain stream errors.
6. Drain streams to EOF or a documented bounded deadline.
7. Finalize once, release every resource and reconcile consumers.

All failures and user cancellation take the same terminal cleanup path,
including failures before any process exists. Register resources as soon as
they are allocated. Terminal cleanup is idempotent. Late filters, timers and
sentinels carry a run identity and cannot mutate a successor.

Do not let descendant processes holding stderr open keep Emacs draining
forever. Cancellation stops pending tasks and invocations and applies a
documented child-process policy; verify behavior on Linux and macOS rather
than assuming deleting the immediate process kills its descendants.

Isolate parser exceptions, individual event validation and individual
subscriber exceptions. A broken consumer must neither discard the tail of
a result batch nor prevent other subscribers or cleanup from running. Treat
consumer errors as presentation errors, distinct from a corrupt runner stream.

Replace repeated whole-pending-string splitting with incremental framing.
Bound event bytes, retained output and queued work independently. Oversized
or malformed structured events produce a visible protocol error. Preserve
human-readable noise; do not silently discard every line beginning with `{`.
Specify UTF-8, CRLF, partial codepoints, final unterminated lines and EOF
behavior in transport tests.

## 6. Discovery, caching and responsiveness

Each discovery response carries source version and completeness: complete,
skipped, failed or cancelled. Only a complete authoritative snapshot can
remove obsolete definitions. Reconcile deleted files separately after a
successful project enumeration; a transient enumeration failure is not an
empty project.

Widen visiting buffers inside `save-restriction`. Cache their discovery by
buffer modification tick plus provider identity. Disk cache keys include
canonical file, provider/query revision, mtime and size. Document the residual
mtime/size limitation and provide explicit invalidation; do not hash every
file on each warm lookup just to defeat the cache's purpose.

Bound the long-lived cache by entries or estimated retained size. Per-run
snapshots remain stable while shared cache entries are replaced or evicted.
Define invalidation for backend re-registration, grammar/query changes,
renames and changed configuration.

Use a worker Emacs for cold project discovery and sufficiently large files,
with a bounded task queue and explicit grammar/backend setup. Batch several
files per worker task to amortize startup; do not spawn an Emacs per file.
Keep a fast in-process path for small current-buffer discovery. Prototype
and measure the crossover before making a fixed threshold public.

The worker reads saved files; unsaved buffers require supplied text snapshots
with version tokens. When saving is disabled, label execution as using disk
contents and avoid presenting unverified buffer positions as exact. Source
edits during a run invalidate navigation certainty, not the historical result.

Store results promptly, then coalesce consumer redraws by file/run. Keep
notification ordering documented. Start with batched UI updates; only add a
more elaborate parser queue if measurements show the parser itself blocks.
If event-loop work is budgeted, expose backlog/completeness and ensure
finalization waits for queued records without unbounded memory growth.

## 7. Backend-specific changes

### Cargo

Resolve actual packages and execution targets using Cargo's metadata/build
information. Associate each test process with its target; never share a
name-only index across executables. Handle binary-only and mixed lib/bin
packages, multiple integration executables and workspace boundaries.

Treat source-to-module inference conservatively: custom target paths,
`#[path]`, shared modules and generated tests can defeat filename heuristics.
Unknown source mapping must retain the result. Build/collection errors become
run errors. Keep the unstable JSON dependency explicit and verify supported
toolchains; toolchain arguments belong in the correct command position.
Do not make a new text parser part of the initial refactor.

### Pytest

Preserve complete nodeids and parameter identity. Aggregate setup/call/teardown
into one case attempt without losing failure information. Keep raw selectors
for exact rerun. Emit collection/session failures and completion metadata.
Map parameter cases to their static definition separately. Cover mixed
parameter outcomes, teardown failure and collection error after valid tests.

### Node

Replace suffix-based file-event suppression with validated event semantics.
Preserve file-level errors. Keep reporter nesting state per execution context.
Separate source name decoding, runtime names and selector generation. Cover
duplicate names, suffix names, literal separators and failed file loading.

### Vitest

Use shared JavaScript helpers without requiring the Node backend. Scope all
transient state to the current invocation. Detect `.only` from syntax and
the run snapshot, ignoring comments and strings; prefer explicit selection
metadata when the supported reporter API supplies it. Preserve uncertainty
where skipped and excluded tests cannot be distinguished.

Support explicit configuration when executable location cannot identify
ownership. Test project configuration and filename-filter semantics so a
file request does not silently broaden into similarly named files.

## 8. Consumers and public usability

- Fringe: derive pending markers from actual selection; restore/reconcile
  on completion, error and cancellation. Aggregate cases at a definition.
- Flymake: use an explicit attest ownership tag for diagnostics, canonical
  paths and correct character coordinates. Preserve other backends' entries.
  Cover visited/unvisited transitions and narrowed buffers.
- Results: show run errors and incomplete status alongside cases; navigate
  only when source mapping is reliable. Offer failing-case reruns even when
  no static definition exists. Keep this a flat table for 1.0.
- Output: include run/invocation headings, commands, exits and protocol errors.
  Define retention explicitly; a historical run must not claim that the next
  run's reused output buffer is its own output. Bound retained runs/output.
- Commands: preserve familiar names and prefix map. Give actionable errors
  for missing grammars, unavailable runners, ambiguous backend selection,
  unsupported exact selection and empty discovery.

Keep cached results separate from pending UI state. Public cache reads return
documented snapshots; mutation goes through one owner that maintains all
indexes and emits cache-change notifications. Batch cache clearing/pruning
notifications so consumers redraw once per affected file.

## 9. Implementation sequence and release gates

Each milestone should finish with a green tree. Use small behavior-focused
commits within a milestone; directory moves and generated fixture updates
should be independently reviewable.

| Milestone | Deliverable | Gate |
|---|---|---|
| M0: reproduce | Promote review probes into committed focused fixtures/tests; record baseline metrics | All known failures demonstrable; baseline tests unchanged |
| M1: containment | Narrowing, startup/pipe cleanup, hook isolation, fringe reconciliation, cache keys, fresh rerun state, Node suffix and `.only` fixes | Relevant regressions pass; no leaked resources or stranded UI |
| M2: layout | Move files, extract ownership boundaries, stage package artifact | Same behavior/tests; cold installed-package smoke test passes |
| M3: model | Definition/case/target IDs, request/run/invocation records, result reducer, public read APIs | Identity and mixed-outcome tests pass; no old ID splitting remains |
| M4: protocol | Versioned backend boundary, cancellable preparation, multiple invocations, completion/error model | Four backends migrated; conformance suite passes |
| M5: backend reliability | Cargo target isolation, pytest phase/case accounting, complete Node/Vitest error handling | Real false-success reproductions fixed; exactness limitations explicit |
| M6: responsiveness | Worker discovery, versioned bounded caches, bounded framing, coalesced UI | Cold/warm/large-file/burst/cancel benchmarks meet budgets |
| M7: release candidate | Documentation, packaging, compatibility matrix, installed-artifact verification | All 1.0 gates below pass |

M3–M5 are a dependency chain. Introduce the case reducer and migrate pytest
first as a manageable vertical slice, then multi-invocation Cargo, then the
JS backends. Keep intermediate adapters private and remove them before the
release candidate. Do not publish an intermediate backend API as stable.

M1 is containment, not permission to release with the false-success findings
still present. Avoid building elaborate temporary identity or Cargo fixes
that M3–M5 immediately replace. If a milestone spans several commits, make
the new regression tests pass as the corresponding behavior lands rather
than permanently marking correctness defects as expected failures.

### Review coverage

| REVIEW-3 finding | Primary milestone |
|---|---|
| 1 Cargo identity; 13 binary-only crates | M3–M5 |
| 2 pytest failure overwritten | M3, M5 |
| 3 narrowed discovery | M1 |
| 4 ID collisions; 5 unrelated position fallback | M3 |
| 6 incomplete execution reported clean | M4–M5 |
| 7 startup; 8 pipe leak; 9 consumer exceptions | M1, then M4 consolidation |
| 10 backend cache collision | M1, then M6 cache lifecycle |
| 11 rerun `.only` state; 16 comment detection | M1 |
| 12 stranded fringe state | M1, then M3 case aggregation |
| 14 Node suffix filtering | M1, then M5 file-error model |
| 15 unbounded framing | M6; run-error semantics from M4 |

## 10. Verification strategy

Keep recorded parser fixtures and a small live integration suite. Add
contract and lifecycle tests rather than multiplying only happy-path ID
parity fixtures. Stress expected failures may document unsupported dynamic
source mapping, but may never excuse losing a reported failure.

Required test groups:

- Identity round trips, aliases, duplicate names, parameter instances,
  executable collisions and ambiguous/unmapped positions.
- Deterministic phase/attempt reduction, repeated events, immutable past-run
  results, selected-scope caching and deleted/renamed definitions.
- Preparation cancellation, failed spawn, signal, nonzero exit before and
  after events, EOF ordering, late callbacks and bounded draining.
- Throwing subscribers, malformed result batches, malformed/oversized lines
  and recovery without dropping later valid events.
- Narrowed/edited buffers, cold and warm cache, changed backend/query,
  eviction, worker failure and stale snapshot responses.
- Each consumer with real run transitions, existing foreign diagnostics,
  unknown locations and repeated case updates.
- Installed artifact with only declared dependencies and bundled assets.

Run correctness on Emacs 30 and 31, Linux and macOS. The existing OS matrix
with one pinned Emacs is not a substitute for a version matrix. Record the
tested runner versions and exercise the oldest claimed and pinned versions;
do not promise every version of Node, Vitest, Cargo and pytest implicitly.

Keep timing benchmarks separate from ordinary ERT correctness. Explicitly
reset caches for cold trials, report median and tail latency over repetitions,
record GC and input sizes, and measure with consumers enabled and disabled.
Use deterministic checks for bounded queue/cache size and linear lookup work.

Proposed reference-machine budgets, to calibrate in M0:

- Preparation/UI callback slices: aim for <=10 ms; investigate >20 ms.
- Small unchanged current-file selection: p95 <=50 ms before spawning.
- Cancellation acknowledgement: <=100 ms while workers/runners are active;
  final forced termination may have a separate documented deadline.
- Worker startup may exceed an interactive slice, but must not block Emacs.
- No project-wide scan per result; no unbounded partial event, queue or cache.

Do not gate noisy shared CI on these exact wall-clock values without a stable
baseline. Gate deterministic bounds there and retain benchmark reports for
trend comparison. Track end-to-end time separately from runner execution time.

## 11. 1.0 scope and completion criteria

Ship the four existing frameworks, all existing commands and consumers,
reliable runtime-case accounting, cancellable discovery, an explicit backend
contract and a working installed package. Static discovery need not expand
every dynamically generated test before execution: runtime results must
remain complete and honest, and selection limitations must be visible.

Keep watch mode, dape integration, a dependency graph, a tree UI, concurrent
user runs, remote/TRAMP execution and persisted historical databases outside
1.0. Detect unsupported remote paths clearly rather than accidentally running
a local process against them. Avoid introducing plugin marketplace machinery,
general RPC infrastructure or a universal runner configuration language.

Before tagging 1.0:

- Every reproduced failure-preservation and lifecycle defect is fixed.
- All four backends pass the same conformance requirements or explicitly
  declare tested capability limits.
- Cancellation and incomplete execution never look like clean success.
- Package installation, asset lookup and autoloaded commands work in isolation.
- Backend/consumer guides include a minimal example and extension ownership
  rules; a trial backend can be added without editing core.
- DESIGN.md describes the implemented contract, not this proposal. Move
  historical assessments/review responses under docs/reviews and update links
  and AGENTS.md. Keep README focused on install, use and supported scope.
- Document the stability boundary: commands and published extension APIs are
  supported; private accessors and internal layouts may change.

Recommended first implementation task: M0 and the focused M1 fixes. Then
complete the mechanical layout change before beginning the model migration.
This establishes a trustworthy baseline and clearer ownership for the work
that changes the extension contract.
