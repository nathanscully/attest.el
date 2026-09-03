# attest.el

Run the test at point, the current file or the whole project from Emacs,
and see failures where you already look: inline through flymake, in the
fringe, in `next-error`. Emacs 30+, no third-party dependencies.

Backends: `node --test`, vitest, `cargo test`, pytest.

## Use

```elisp
(add-to-list 'load-path "~/projects/attest.el")
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
