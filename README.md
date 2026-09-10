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
(add-to-list 'load-path "~/projects/attest/lisp")
(require 'attest-all)
(global-attest-flymake-mode 1)
(global-attest-status-mode 1)
(keymap-global-set "C-c t" attest-prefix-map)
```

One `load-path` entry is enough. `attest-all` loads the core, the four
backends and the three consumers, and a source checkout keeps those in
subdirectories that it adds itself, so the list never has to be written
out by hand. An installed package is flat and that step does nothing.

A backend whose runner is not installed costs nothing but the load, since
backends are chosen per buffer. To load fewer from a source checkout, add
the subdirectory holding each file you want — `lisp/core`,
`lisp/backends/NAME`, `lisp/consumers` — and require it; `attest` plus one
backend is the minimum, and every consumer is optional.

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
nix develop        # the dev shell, with every command and the pinned toolchain
nix develop -c check   # compile (warnings are errors), checkdoc and ert
```

`menu` lists every command in the shell. Without nix, set
`EMACS_TREE_SITTER_GRAMMARS` to a directory of grammar libraries if
Emacs cannot find `typescript`, `rust` or `python`. Integration tests spawn node, cargo, pytest and
vitest when available and skip otherwise; `pnpm install` in
`test/fixtures/vitest` provides vitest.

See `DESIGN.md` for the backend contract and `ASSESSMENT.md` for what
works and what does not. `docs/CONTEXT.md` defines the domain vocabulary;
`docs/reviews/` keeps the reviews and the 1.0 roadmap that produced the
current design.

## License

GPL-3.0-or-later. See `LICENSE`.
