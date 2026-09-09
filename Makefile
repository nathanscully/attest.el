EMACS ?= emacs
DIRS := lisp lisp/core lisp/backends/shared lisp/backends/node lisp/backends/vitest lisp/backends/cargo lisp/backends/pytest lisp/consumers
CORE := lisp/core/attest-model.el lisp/core/attest-backend.el lisp/core/attest-discovery.el lisp/core/attest-results.el lisp/core/attest-run.el lisp/backends/shared/attest-javascript.el
SRC := $(CORE) lisp/attest.el lisp/backends/node/attest-node.el lisp/backends/vitest/attest-vitest.el lisp/backends/cargo/attest-rust.el lisp/backends/pytest/attest-pytest.el lisp/consumers/attest-flymake.el lisp/consumers/attest-status.el lisp/consumers/attest-list.el lisp/attest-all.el
ASSETS := lisp/backends/node/attest-node-reporter.mjs lisp/backends/vitest/attest-vitest-reporter.mjs lisp/backends/pytest/attest_pytest.py
PACKAGE := build/attest-0.1.0
TESTS := $(filter-out test/attest-stress-test.el,$(wildcard test/*-test.el))
STRESS := test/attest-stress-test.el
LOAD := --eval '(setq load-prefer-newer t)' $(addprefix -L ,$(DIRS)) -L test

.PHONY: all compile checkdoc test stress autoloads package package-test clean

all: compile checkdoc test

compile:
	$(EMACS) -Q --batch $(LOAD) --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile $(SRC)

checkdoc:
	$(EMACS) -Q --batch $(LOAD) -l test/run-checkdoc.el $(SRC)

test:
	$(EMACS) -Q --batch $(LOAD) -l test-helper $(patsubst %,-l %,$(TESTS)) -f ert-run-tests-batch-and-exit

stress:
	$(EMACS) -Q --batch $(LOAD) -l test-helper -l $(STRESS) -f ert-run-tests-batch-and-exit

autoloads:
	$(EMACS) -Q --batch -l scripts/package.el $(SRC) $(ASSETS)

package: autoloads
	tar -cf $(PACKAGE).tar -C build attest-0.1.0

package-test: package
	$(EMACS) -Q --batch -l test/package-smoke.el $(PACKAGE).tar

clean:
	rm -f $(SRC:.el=.elc) test/*.elc
