# neotest.el

Run the test at point, the current file or the whole project from Emacs,
and see failures where you already look: inline through flymake, in the
fringe, in `next-error`. Emacs 30+, no third-party dependencies.

Backends: `node --test` (JavaScript and TypeScript).

## Use

```elisp
(add-to-list 'load-path "~/projects/emacs-neotest")
(require 'neotest)
(require 'neotest-node)
(require 'neotest-flymake)
(require 'neotest-status)
(require 'neotest-list)
(global-neotest-flymake-mode 1)
(global-neotest-status-mode 1)
(keymap-global-set "C-c t" neotest-command-map)
```

| key | command |
|---|---|
| `C-c t t` | `neotest-run-at-point` |
| `C-c t f` | `neotest-run-file` |
| `C-c t p` | `neotest-run-project` |
| `C-c t r` | `neotest-rerun-last` |
| `C-c t x` | `neotest-rerun-failed` |
| `C-c t k` | `neotest-kill` |
| `C-c t o` | `neotest-show-output` |
| `M-x neotest-list` | results table |

Failures also appear in `flymake-show-buffer-diagnostics` and
`flymake-show-project-diagnostics`.

## Develop

```sh
make all
```

Runs byte-compile, checkdoc and ert. Set `EMACS_TREE_SITTER_GRAMMARS`
to a directory of grammar libraries if Emacs cannot find `typescript`.

See `DESIGN.md` for the backend contract and `ASSESSMENT.md` for what
works and what does not.
