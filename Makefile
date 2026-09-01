EMACS ?= emacs
SRC := neotest.el neotest-treesit.el neotest-node.el neotest-vitest.el neotest-rust.el neotest-pytest.el neotest-flymake.el neotest-status.el neotest-list.el
SRC := $(wildcard $(SRC))
TESTS := $(wildcard test/*-test.el)
LOAD := -L . -L test

.PHONY: all compile checkdoc test clean

all: compile checkdoc test

compile:
	$(EMACS) -Q --batch $(LOAD) --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile $(SRC)

checkdoc:
	$(EMACS) -Q --batch $(LOAD) -l test/run-checkdoc.el $(SRC)

test:
	$(EMACS) -Q --batch $(LOAD) -l test-helper $(patsubst %,-l %,$(TESTS)) -f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc test/*.elc
