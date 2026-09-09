# Fresh review toward 1.0

Reviewed `fa87880` across the whole project, including DESIGN.md,
ASSESSMENT.md and REVIEW-2-RESPONSE.md. This is a review, not an
implementation change. Findings below distinguish reproduced behavior
from architectural recommendations. P1 means incorrect results or a
substantial reliability problem; P2 means a narrower defect or hardening
needed before stabilizing the extension API.

The built-in consumers and independent backends are a good foundation.
The main obstacle to 1.0 is that identity, run completion and discovery
authority are still underspecified. Several fixes in the previous review
solve a symptom while leaving those contracts ambiguous. I would resolve
these before adding more frameworks.

## Verification

- `nix develop -c make all`: byte compilation and checkdoc pass;
  all 105 ERT tests pass, including all four live runner integrations.
- `nix develop -c make stress`: all 20 outcomes match expectations;
  three dynamic-name tests are expected failures.
- Additional batch-Emacs probes reproduced the findings described below.
  Small real Cargo and Node projects reproduced the backend failures.
  Temporary probes and projects were created under `/private/tmp/attest-review-*`.
- No open PR for `main` was returned by `gh pr list`; the supplied previous
  review response was considered. No source fixes were made.

## Findings

### 1. P1: Cargo test identity loses the executable/target

Location: `attest-rust.el:128`, `attest-rust.el:174`, `attest-rust.el:207`.

The Rust index maps only libtest's test name to one position. Those names
are unique within an executable, not across a crate's library, binaries
and integration test executables. Later positions replace earlier ones.
The stdout stream does not restore the missing executable identity.

Reproduced with `src/lib.rs` containing a failing `#[test] fn same()` and
`tests/integration.rs` containing a passing `#[test] fn same()`. A project
run reports **1 passed, 0 failed** and retains only
`tests/integration.rs::same`, passed. The library failure disappears.

Target runs also omit Cargo target selection, so just changing the
project index is insufficient: another executable can report the same
selected name and overwrite the requested test's result.

Fix direction: identify Cargo targets explicitly and associate each
event stream with its executable. Allow one logical run to contain
multiple process specifications, or another reliable source of target
identity. Never resolve an ambiguous name by overwriting a hash entry.

### 2. P1: Pytest parameter cases can turn a failure green

Location: `attest-pytest.el:140`, `attest.el:630`.

The parser strips parameter suffixes and core replaces the result at that
ID. Replaying `test_case[bad]` failed followed by `test_case[good]` passed
leaves one passing result and no rerunnable failures.

Parameterized discovery is explicitly deferred, but silently losing a
failure is a separate reliability defect. The current expected-failure
stress tests do not enforce preservation of failure information.

Fix direction: give runtime cases distinct identities linked to a static
definition. As an interim measure, aggregate outcomes conservatively
and preserve failing runner selectors. Also define how setup/call/teardown
events combine, rather than treating every event as unconditional replacement.

### 3. P1: Narrowing changes discovery and can prune valid cached results

Location: `attest.el:367`, `attest.el:421`, `attest.el:767`.

Discovery uses the visiting buffer's current restriction without widening.
In the existing Node fixture, narrowing to one test changes discovery
from nine positions to one. File-scope pruning then treats the missing
positions as deleted tests. An enclosing suite can also disappear from
the discovered ancestry, changing IDs and selectors.

Fix direction: use `save-restriction` and `widen` around whole-file
discovery. Preserve the user's restriction. Add a narrowed-buffer test
that asserts complete identity, selection and cache preservation.

### 4. P1: IDs are not an unambiguous representation of identity

Location: `attest.el:219`, `attest.el:745`.

`attest-make-id(file, "a::b")` equals
`attest-make-id(file, "a", "b")`. A literal test name and a nested path
can collide; converting the first ID to a Node selector changes the
literal `::` to a space. Repeated sibling test names also collapse.

File canonicalization is applied to auxiliary indexes, but not to IDs
or target membership. A probe using two spellings of the same physical
file returned `file-equal-p = t` and `attest-target-result-p = nil`.
Such a result is discarded before position lookup can repair anything.

Fix direction: represent canonical file identity and name segments
separately from display strings and runner selectors. Use an unambiguous
encoding for public string IDs. Define duplicate-name/instance identity
before third-party backends depend on this format.

### 5. P1: Position fallback borrows locations from unrelated files

Location: `attest.el:489`; regression test `test/attest-review2-test.el:47`.

After an exact lookup misses, core searches every file in the run for
matching names. It never verifies that the position belongs to the same
physical file. A result for `/tmp/unrelated.test.ts::same` can receive the
line and column of `demo.test.ts::same`; reproduced with line 99.

The existing regression test explicitly accepts a path under
`/other/root/` without establishing an alias. That test blesses the
misattribution and should change with the implementation.

This is also a performance problem: an unmatched runtime result scans
the project's positions, repeatedly splitting their IDs. With R unmatched
results and P positions, this path can cost O(R × P).

Fix direction: normalize the file, then perform a lookup within that
file only. Remote or rewritten paths need an explicit backend mapping;
an unknown position should remain unknown.

### 6. P1: Any recorded result masks a later runner failure

Location: `attest.el:967`.

The sentinel treats any non-signal exit as `finished` if even one result
was recorded. A stub runner printing one passing event and exiting 2
produced `status=finished`, exit 2, and a clean passing summary. Similar
behavior can hide collection failures or a runner abort after partial
execution. With no failed test result, `on-failure` does not show output.

Fix direction: retain exit code and distinguish process completion,
test outcomes and run/infrastructure errors. Let a backend interpret its
exit codes and completion events; merely allowing every nonzero exit
after the first event is too permissive. Cargo's expected test-failure
exit is a reason for backend classification, not for dropping the distinction.

### 7. P2: Startup does not have one guaranteed cleanup path

Location: `attest.el:993`.

The error handler covers command construction and process spawning
separately. Missing commands, discovery/grammar errors during pruning,
output-buffer initialization and started-hook failures fall between them.
A backend returning no command left `:status` as `running` and the
progress timer alive. `attest-kill` cannot clean up a run with no process.
Command-construction errors clear the timer but do not notify finished
consumers or set an end time.

Fix direction: make preparation, spawning and terminal cleanup one
exception-safe lifecycle. Every accepted run should terminate exactly
once, including cancellation during preparation. Validate command specs
before allocating resources or notifying process-start consumers.

### 8. P2: Failed spawning leaks the stderr process

Location: `attest.el:1032`.

`make-pipe-process` succeeds before `make-process` is called, but the pipe
is stored on the run only after both succeed. A missing executable leaves
an unattached live `attest-stderr` process. Comparing `process-list`
before and after the existing failed-spawn scenario reproduced the leak.

Fix direction: register ownership immediately and release the pipe on
every failed spawn. Extend the regression test to assert resource cleanup,
not just the final run status.

### 9. P2: Consumer errors discard valid results from a batch

Location: `attest.el:904`, `attest.el:630`, `attest.el:938`.

One handler surrounds parsing, all records in the returned batch, and
result hooks. If a consumer throws while receiving the first result,
the remaining results are discarded and the error is called a backend
parse failure. A two-result batch with a throwing consumer stored only
the first ID. A failing hook also prevents later subscribers from running.

Fix direction: isolate parser failure, result validation/storage, and
individual subscriber failures. Store every valid event independently.
Record errors on the run and preserve cleanup and other notifications.
Documenting that hooks must be fast does not address exception isolation.

### 10. P2: Discovery cache ignores which backend/query produced it

Location: `attest.el:421`.

The cache key is the file's true name, with mtime and size as the stamp.
It does not include backend, language or query. After discovering nine
positions with Node, querying the same unchanged file through an empty
backend query still returned those nine positions.

Fix direction: include discovery-provider/query identity or a revision
in the cache key, and invalidate appropriately on backend registration
or configuration changes. This matters when several frameworks share a
language, even though the two current JS backends share a query.

### 11. P2: Reruns reuse Vitest's previous `.only` decision

Location: `attest.el:1070`, `attest-vitest.el:161`.

Restart shallow-copies the run and clears four fields, but leaves the
`:vitest-only` hash table intact. The old and new runs share that table
(confirmed by `eq`). Adding or removing `.only` and rerunning reuses the
old decision, either recording excluded skips or suppressing genuine skips.

Fix direction: construct a fresh run from the request, not from the entire
mutable execution record. Keep backend transient data inside a resettable
backend-state field. Contributors should not need to modify core's reset
list whenever they add cached state.

### 12. P2: Fringe status marks unrelated tests running and never restores them

Location: `attest-status.el:132`, hook registrations at end of file.

The start handler marks every discovered cached result in a touched file
as running, without checking target membership. A one-test target run
with two cached tests painted both as running. The consumer has no
finished hook, so the unselected test never leaves that state. A killed
run or a skipped suite can strand markers for the same reason.

Fix direction: derive pending markers from the actual selection and
reconcile them on every terminal outcome. Keep transient execution state
separate from the previous result so interruption can restore it.

### 13. P2: Rust file runs fail in a binary-only crate

Location: `attest-rust.el:137`.

Every `src/` file adds `--lib --bins`. A minimal Cargo package containing
only `src/main.rs` and one test fails with `no library targets found`.
This was reproduced through `attest-run` using the pinned toolchain.

Fix direction: discover actual Cargo targets and select the executable
owning the file. Avoid requiring a library target that does not exist.
This belongs with the target identity work in finding 1.

### 14. P2: Node's file-event heuristic drops legitimate tests

Location: `attest-node-reporter.mjs:33`.

The reporter suppresses any event whose test name is a suffix of its file
path. A real `attest-review-suffix.test.mjs` containing tests named `mjs`
and `ordinary` yielded only `ordinary`. The same filter also suppresses
file-level failure events, so there is no structured representation for
those errors.

Fix direction: distinguish file/execution failures using event metadata
and explicit error events. A suffix comparison is not a test-kind check.
Add a live regression for legitimate suffix names and file-level errors.

### 15. P2: Output limits do not bound the structured stream

Location: `attest.el:891`, `attest.el:879`.

The partial-line slot grows without limit until a newline arrives. A
probe accumulated 2 MiB there, separate from the capped output buffer;
the code has no upper bound. Each chunk concatenates and splits the full
pending string again, giving quadratic copying for a long unterminated
line. A truncated large JSON event or arbitrary stderr output can stall
Emacs and grow memory despite `attest-max-output`.

The JSON helper also silently drops malformed lines beginning with `{`,
which makes diagnosis harder.

Fix direction: set a configurable structured-event size limit, scan new
chunks incrementally, and report framing/JSON failures visibly. Dropping
an oversized event must mark the result stream incomplete rather than
allowing a clean success summary.

### 16. P2: Vitest `.only` detection mistakes comments and strings for code

Location: `attest-vitest.el:145`.

The detector is a regexp over raw text. A comment saying
`// Remember to remove test.only before committing` is treated as a real
exclusive test declaration. The parser then discards genuine skipped/todo
results in that file, preserving stale status instead of recording the skip.

Fix direction: inspect syntax using the tree already available, and keep
the decision tied to the run's source snapshot. The previous review's
reporter limitation does not justify interpreting comments as declarations.

## Performance assessment

The per-file result index and per-run position tables are sensible. Keep
them. Avoid claiming the current stress timing establishes cold discovery
performance: `attest-stress--check-discovery-timing` does not clear the
global cache, and earlier tests warm it. This run reported Node discovery
at 0.9 ms/file after a Node project run.

A separate temporary-buffer probe, with no disk position-cache hits,
measured 1,000/4,000/8,000 simple JS tests at approximately
34/109/338 ms respectively. These are local measurements, not a stable
benchmark or proof of one particular bottleneck. They show that even a
single open file can exceed an interactive latency budget. A file-size
limit does not constrain already visited buffers.

Before making performance claims for 1.0, test these independently:

- Cold discovery, warm discovery and edited visiting-buffer discovery.
- Many small files and one large file, with consumer modes enabled.
- Unknown result IDs, repeated test names and path aliases.
- Large streamed bursts, malformed events and cancellation latency.

Track wall-clock responsiveness as well as total throughput. Chunked
discovery between files helps large repositories; a child Emacs or another
bounded approach is needed if one parse itself takes hundreds of ms.
Move discovery out of backend `:command` so core can schedule and cancel
it consistently. Reuse visiting-buffer discovery by modification tick
where safe, including provider identity and the full-buffer restriction.

## Contract changes I would make before 1.0

1. **Separate definitions, runtime cases and selectors.** A position
   describes source; a runtime result may be one of many instances of it;
   the runner selector is backend-specific. Canonical file identity,
   executable identity and raw name segments must not be recovered by
   splitting a display string. Keep the existing public helpers where
   useful, but define the underlying model first.

2. **Separate a request from an execution.** A request holds scope,
   backend, root and targets. A fresh execution owns its state, processes,
   discovery snapshot, errors and results. Rerun creates a new execution
   from the request. This makes lifecycle cleanup and backend extension
   substantially less fragile. A struct is an option, not the objective;
   changing plists to structs alone fixes none of the semantic issues.

3. **Make discovery and completion explicit protocols.** Discovery should
   distinguish complete, skipped, failed and cancelled; only complete
   discovery authorizes pruning. Supply a common tree-sitter implementation,
   with a deliberate extension boundary for framework collection or
   normalization when static names are insufficient. Completion should
   retain exit status, completeness and run-level errors. Consumers should
   not infer these from whether some results happened to arrive.

4. **Let one run own multiple executions when required.** Cargo provides
   a concrete need today. A backend can describe several executable/target
   invocations while core handles scheduling, output, cancellation and
   aggregation. This need not add concurrent user runs or a tree UI.

5. **Publish a backend conformance suite.** Validate registration/specs
   and document required fields, units, coordinate conventions, mutation
   ownership and state lifetime. Exercise identity, namespaces, unknown
   tests, duplicate events, failures before/after results, cancellation,
   reruns and subscriber exceptions. Add an explicit backend override so
   contributors and users can resolve ambiguous framework dispatch.

Retain the built-ins-only approach and independent consumers. A larger
framework rewrite is not necessary, but the contracts above deserve
intentional changes while compatibility is still inexpensive. Prioritize
false-success and identity fixes first, then lifecycle and state isolation,
then discovery responsiveness, and only then expand the backend surface.
