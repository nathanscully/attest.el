# Review 2: what changed

Response to the 49-item review of `attest.el`. Every item is addressed.
Baseline `e9d3cb2`, head `b8f5a2e`, 16 commits, 48 files, +1707/-242.

Tests: 59 to 97 in the main suite, 19 to 20 in stress. Each new test was
run against the unfixed code first and confirmed red; three findings are
recorded below as rejected, with the evidence.

CI green on `b8f5a2e` across `check (ubuntu-latest)`, `check (macos-latest)`
and `stress`.

## Commit map

| commit | items | what it does |
|---|---|---|
| `04bc7c3` | 3, 4, 7, 15, 22, 48 | killed run stops writing into the next one |
| `0960a4c` | 2-perf, 5, 9, 17, 18, 19-part, 34, 45 | per-file result index, truename paths |
| `fc448e2` | 8, 32, 33, 39, 40, 41, 42, 43, 44 | consumer fixes |
| `9969698` | 1, 10, 11, 13, 25, 36, 49 | node reporter and vitest dispatch |
| `9f35df2` | 2, 14, 16, 47 | rust file scope |
| `5ec2c88` | 6, 37, docs | pytest teardown, doc corrections |
| `c19561a` | 28, 29, 30 | drop url-util, `:names`, duplicated helper |
| `70376b2` | 24 | one JSON line parser |
| `160599c` | 12 | project run from any file |
| `db91204` | 26 | one position index per run |
| `ededff1` | 27, 31 | run plist invariant |
| `6c292e7` | 38 | `attest-all` and autoloads |
| `bb908a5` | 20 | progress before discovery blocks |
| `4889abb` | 21 | parse cache keyed on mtime and size |
| `f4108c8` | 19 | bounded output buffer |
| `b8f5a2e` | 23, 46 | single-run constraint documented |

## Bugs fixed

### Killed run wrote into its successor (`04bc7c3`, item 3)

`attest-kill` deleted the child but left `:stderr-process` alive with a
filter closed over the finished run. Confirmed directly: after a kill the
pipe reported `(open listen connect stop)`. The pipe is now deleted, and
both filters no-op unless the run is still `running`.

Four more in the same commit. Stderr drained for a single 0.1s window, so
a large final JSON batch could be cut off; it now reads until empty.
`attest--feed-lines` split on `"\n"` only, so a CRLF runner left a
trailing `\r` and every line failed to parse. Neither pipe set `:coding`,
so non-ASCII test names broke under a non-UTF-8 locale. A failed spawn
called `attest--finish` and then re-signalled, so the user got a summary
followed by a debugger.

Item 4: the finish summary counted namespaces as tests. A file with 7
tests and 2 failing suites reported "4 passed, 3 failed". It now counts
`:type 'test` only.

### Path comparison missed the same file (`0960a4c`, item 5)

Result lookup compared paths with `string=`. Measured: a file recorded
under its real path and read back through a symlink returned **0
results**. Same class as `/var` against `/private/var` on macOS. Keys are
now truenames.

### Rust file runs left the file (`9f35df2`, item 2)

Module prefix is empty for `src/lib.rs`, `src/main.rs` and `tests/*.rs`,
and an empty prefix passed **no filter at all**, so a file run built and
ran the whole crate. Unmapped events then fell back to the run's own
file, so a test from `scanner.rs` was recorded as living in `lib.rs`.

The integration test's expected count of 5 was 4 real tests plus that
leak, exactly as the review said (item 47). It now asserts the name set
and every result's `:file`.

Events outside the run index are dropped, and the command passes
`--lib --bins` for a `src/` file or `--test NAME` for an integration
test, so cargo stops running the rest.

### Pytest reported broken teardowns as passing (`5ec2c88`, item 6)

Verified against real pytest. The old plugin emits one event for
`test_teardown_fails`:

```
{"nodeid": "...::test_teardown_fails", "outcome": "passed", "when": "call"}
```

and nothing else. The fixed plugin adds:

```
{"nodeid": "...::test_teardown_fails", "outcome": "failed", "when": "teardown",
 "crash": {"message": "RuntimeError: teardown boom"}}
```

A test that destroys state on the way out was reported green.

### Project runs failed from a non-test file (`160599c`, item 12)

`attest-run-project` resolved its backend with the same predicate as
`run-file`, so from `src/index.ts` it said "no backend". Backends now
declare `:project-p`, asked only for a project run. `:predicate` is the
fallback, so an out-of-tree backend is unaffected. The node mode list
also picks up `typescript-mode`, `js2-mode`, `rjsx-mode` and `web-mode`,
which never matched before.

### Node reporter mixed files (`9969698`, item 1)

One module-global stack keyed only by nesting depth. Replaying an
interleaved stream through the old reporter attributes `alpha.test.mjs`
tests to `beta suite`; keyed by file they land under `alpha suite`.

See the rejected findings below for why this was not reachable in
practice, and why the fix stands anyway.

### Consumers stranded state (`fc448e2`, items 8, 43)

Pruning drops a deleted test from the cache, but the fringe consumer only
repainted ids it still knew, so the overlay for a deleted test survived
until the mode was toggled. Markers are now rebuilt on run start.

The flymake refresh cleared the whole `flymake-list-only-diagnostics`
entry for a file, discarding other backends' diagnostics. It now removes
only attest's own, identified by the result plist it passes as diagnostic
data, and drops the entry only when nothing else remains.

Item 42: `attest-flymake-mode` now turns on `flymake-mode`, since without
it the mode reports nothing. `attest-flymake-auto-enable-flymake` opts
out. Item 44: `attest-list-visit` used `move-to-column`, a display
column, against a character offset, so it missed on a line with tabs.

## Performance

| | before | after |
|---|---|---|
| `attest-results-for-file`, 5000 results / 200 files | 14.78 ms | 0.04 ms |
| discovery, 50 files, repeat run | 632 ms | 10 ms |
| run start to first sign of life, 50 files | 661 ms | 58 ms |

Item 18: the result cache was one flat hash, walked in full by
`attest-results-for-file`, prune, flymake and the fringe consumer. The
fringe consumer does this once per live buffer per run, so with 50
buffers open that was roughly 740 ms of scanning. Now a per-file index.

Item 20: discovery parses every file in scope on the Emacs thread before
the runner starts, and the progress message came *after* it. That whole
stretch was frozen and silent, which reads as a hang. The message now
lands at 58 ms and the parse runs behind it. Chunked or child-Emacs
discovery is still the roadmap item; this is the interim.

Item 21: positions are cached against modification time and size. A
buffer visiting the file is still parsed directly, so unsaved edits are
never served from the cache; verified.

Item 19: the output buffer grew without limit during a run. Now bounded
at `attest-max-output` (2MB), oldest dropped with a visible marker.
`attest-clear-results` landed in `0960a4c`.

## Three findings rejected, with evidence

### `--exact` does not do what the review expects (item 2 tail)

The recommendation was to pass `--exact` whenever the prefix is
non-empty. libtest compares `--exact` against the full test path, so a
module prefix matches nothing. On cargo 1.97.0:

```
$ cargo test -q --lib -- scanner --exact
test result: ok. 0 passed; 0 failed; 6 filtered out
```

All six tests filtered out. Appending the module separator is what
actually excludes the sibling over-match:

```
$ cargo test -q --lib -- 'scanner::'
test result: ok. 1 passed; 5 filtered out
```

Shipped the separator.

### The node concurrency flake is unreachable (item 1)

The review says the stress parity test "can pass on a quiet machine and
flake under load". It cannot. Node's head-of-line gate in
`lib/internal/test_runner/test.js` serialises `test:start`/`test:pass`/
`test:fail` per file across versions 18 to 24: only one `FileTest` emits
at a time and the rest buffer. Measured at `--test-concurrency=4` with
200 slow tests per file: 402 events from file A contiguous, then 402
from B.

The fix ships anyway, because the reporter should not depend on an
undocumented invariant. The regression test replays a recorded
interleaved stream through the real `.mjs`, so it is deterministic rather
than racing a live run.

### Vitest `.only` cannot be filtered as suggested (item 10)

Both suggested approaches are impossible. `interpretTaskModes` in
`packages/runner/src/utils/collect.ts` overwrites `t.mode = 'skip'` in
place during collection, before any reporter hook runs. `mode`, `state`,
`note` and `diagnostic()` are byte-identical for an `.only`-excluded test
and an author-written `test.skip`. The reporter has nothing to filter on.

Detection reads the source instead: skipped results are dropped when any
file in the run declares `.only`.

## One finding understated

Item 33 says the mode-line construct is "harmless visually". It is worse
than that. `attest--progress-start` did:

```elisp
(append (if (listp mode-line-process) mode-line-process (list mode-line-process))
        '(attest--progress))
```

With `mode-line-process` nil this is `(append nil '(attest--progress))`,
which returns the quoted constant itself. Byte-compiled, that literal is
shared, so the suggested in-place removal would have mutated it for every
later run. Fixed with `copy-sequence` before appending and `remq` on
stop.

## `cl-defstruct` deliberately not done (items 27, 31)

The three plist cases were measured before deciding:

| case | result |
|---|---|
| `plist-put` on a copy, key present | safe, `copy-sequence` shares no tail |
| `plist-put` adding a key to a non-empty plist | safe, visible without `setq` |
| `plist-put` on nil | **write silently lost** |

Only the third is a real hazard, and it means a run built by hand rather
than through `attest--make-run`. A `cl-defstruct` would break every
backend and test that reads the run with `plist-get`, for a problem that
has one shape. `attest--start` now checks the invariant it depends on, so
such a run fails at the point of the mistake rather than several keys
later.

## Packaging (item 38)

Setup was eight `require` forms, and the autoloaded commands do not work
without them: `attest-run-file` resolves a backend, and with none loaded
it only reports there is none.

`attest-all.el` loads the core, four backends and three consumers.
`make autoloads` generates `attest-autoloads.el` with `loaddefs-generate`;
it is not tracked. Verified from a cold Emacs holding only the autoloads:
commands autoload, and `attest-all-load` registers all four backends with
vitest ahead of node.

## Docs corrected

- README load-path named a directory the repo does not use.
- README now states tree-sitter and per-language grammars are a hard
  runtime requirement, and that cargo runs set `RUSTC_BOOTSTRAP=1`
  through `attest-rust-environment`.
- DESIGN covers the per-file result index, `attest-cache-result` and
  `attest-clear-results`, and records that attest tracks one run at a
  time (item 46).
- DESIGN's "not building" list claimed a second backend was undecided and
  that discovery skipped unopened files. Four backends shipped, and
  discovery reads any file a run covers.
- ASSESSMENT's line and test counts are dropped rather than left to
  drift.
- Hook contract documented on all three abnormal hooks: must be fast,
  must not re-enter `attest-run` (item 23). Queueing results off the
  process filter is a larger change and is not done.

## New user-facing knobs

| name | default | why |
|---|---|---|
| `attest-max-file-size` | 512k | discovery skips larger files so one generated file cannot stall a run |
| `attest-max-output` | 2MB | bounds the output buffer |
| `attest-flymake-auto-enable-flymake` | t | set nil to manage `flymake-mode` yourself |
| `attest-rust-environment` | `("RUSTC_BOOTSTRAP=1")` | replace to use a nightly toolchain instead |
| `attest-project-skip-directories` | node_modules, .git, target, … | only for a root `project-current` does not know |

New commands: `attest-clear-results`, `attest-invalidate-positions`.
New function: `attest-cache-result`, so a caller seeding the cache cannot
desynchronise it from the file index.

## Follow-up round (`6bf894c`)

The reviewer read the above and found seven blockers, all correct. This
document originally said "nothing remains", which was wrong. Fixed:

1. **Item 20 was only fixed for node and pytest.** Rust indexes its
   crate inside `:command`, which ran before the progress message.
   Measured: 395 ms of silence for the 40 files of `stress/cargo`.
   Progress now starts before `:command`; the message lands at 53 ms. A
   `:command` that signals clears the indicator instead of leaving it
   spinning.

2. **Rust crate-root file scope still ran sibling modules.**
   Mis-attribution was fixed, extra execution was not. Confirmed against
   cargo: `--lib --bins` with no filter reports `0 filtered out`, so
   `scanner.rs` and `scanner_other.rs` ran and were discarded. Passing
   the file's own names with `--exact` reports `2 filtered out`.

3. **Path identity was half-applied.** `attest--progress-buffers` still
   used `member`, and the per-run position index keyed on
   `expand-file-name`, so a runner naming a file differently lost
   discovery's line and column. Both key on true names now, with a
   name-based fallback across the run's files.

4. **`attest-clear-results` did not reach the consumers.** It fired
   `attest-run-finished-functions` with the last run: the fringe
   consumer is not on that hook, and a prefix-arg clear of file A named
   file B. New `attest-results-changed-functions` carries the files that
   changed; all three consumers subscribe, and the list drops rows the
   cache no longer holds.

5. **Wrong ANSI variable.** `ansi-color-apply-on-region` reads
   `ansi-color-context-region`; the mode reset `ansi-color-context`.

6. **Vitest `.only` was project-global.** One `.only` stopped genuine
   `test.skip` updating in every other file of the run. Now per file,
   which also reads each file lazily rather than scanning the project on
   the first skipped event.

7. **`attest-all.el` header was truncated.** The licence block started
   mid-sentence and `;;; Commentary:` appeared twice. checkdoc passed it.
   Rebuilt from the core file, now byte-identical.

Plus the smaller notes: `attest-cache-result` left a ghost when an id
moved between files; prune no longer treats a file skipped for size as
having lost its tests; `attest-rust--project-p` now requires a rust mode
like the other backends; the process-test stub's `:root` matches the
`(file) -> dir` contract.

Two of these were bugs in the first round's own new code (5 and 7), and
one had never worked: `mode-line-process` crashed on a string value,
because `memq` rejects a string, so the restoration written for exactly
that case could not run. Both found by writing the test first.

Tests: 97 to 105. Five of the seven new tests were red against the
previous head; the two that were not are noted in the file, and one of
them was rewritten after it turned out to pass for the wrong reason
(`expand-file-name` already reconciles a same-directory symlink, so it
was not exercising the fallback at all).

## Not done

The open work is the pre-existing roadmap: chunked or child-Emacs
discovery for repo-wide indexing, and `test.each` / parametrized names,
tracked by the `stress/*/dynamic*` files whose parity tests are declared
`:expected-result :failed`.

Knowingly left: the position cache never evicts, which is fine for a
session and has `attest-invalidate-positions` as the escape hatch.
Queueing results off the process filter (item 23) is still only
documented, not implemented.
