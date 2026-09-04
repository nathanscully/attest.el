# attest.el

Run the test at point, the current file or the whole project from Emacs,
and see failures where you already look: inline through flymake, in the
fringe, in `next-error`. Emacs 30+, no third-party dependencies.

Backends: `node --test`, vitest, `cargo test`, pytest.

Requires an Emacs built with tree-sitter, plus the grammar for each
language you run tests in (`typescript`, `tsx`, `javascript`, `rust`,
`python`). An Emacs without tree-sitter support signals an error on
load; a missing grammar signals a user-error naming the language when
you run a test in it. Install the grammars before first use; see
`EMACS_TREE_SITTER_GRAMMARS` below.

## Use

```elisp
(add-to-list 'load-path "~/projects/attest")
(require 'attest)
(require 'attest-node)
(require 'attest-vitest)
(require 'attest-rust)
(require 'attest-pytest)
(require 'attest-flymake)
(require 'attest-status)
(require 'attest-list)
(global-attest-flymake-mode 1)
(global-attest-status-mode 1)
(keymap-global-set "C-c t" attest-prefix-map)
```

| key | command |
|---|---|
| `C-c t t` | `attest-run-at-point` |
| `C-c t f` | `attest-run-file` |
| `C-c t p` | `attest-run-project` |
| `C-c t r` | `attest-rerun-last` |
| `C-c t x` | `attest-rerun-failed` |
| `C-c t k` | `attest-kill` |
| `C-c t o` | `attest-show-output` |
| `M-x attest-list` | results table |

Failures also appear in `flymake-show-buffer-diagnostics` and
`flymake-show-project-diagnostics`.

The `cargo test` backend reads libtest's JSON output, which sits behind
an unstable rustc flag. `attest-rust-environment` sets
`RUSTC_BOOTSTRAP=1` by default so stable rustc accepts it. That
variable unlocks every unstable rustc feature for the crate under test,
not just this one, and some organisations ban it. On a nightly
toolchain, set `attest-rust-environment` to nil and add the toolchain
switch to `attest-rust-cargo-args` instead.

## Develop

```sh
make all
```

Runs byte-compile, checkdoc and ert. Set `EMACS_TREE_SITTER_GRAMMARS`
to a directory of grammar libraries if Emacs cannot find `typescript`,
`rust` or `python`. Integration tests spawn node, cargo, pytest and
vitest when available and skip otherwise; `pnpm install` in
`test/fixtures/vitest` provides vitest.

See `DESIGN.md` for the backend contract and `ASSESSMENT.md` for what
works and what does not.

## License

GPL-3.0-or-later. See `LICENSE`.
