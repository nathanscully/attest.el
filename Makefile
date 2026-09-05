EMACS ?= emacs
SRC := attest.el attest-node.el attest-vitest.el attest-rust.el attest-pytest.el attest-flymake.el attest-status.el attest-list.el attest-all.el
SRC := $(wildcard $(SRC))
TESTS := $(filter-out test/attest-stress-test.el,$(wildcard test/*-test.el))
STRESS := test/attest-stress-test.el
LOAD := -L . -L test

.PHONY: all compile checkdoc test stress autoloads clean

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
	$(EMACS) -Q --batch --eval '(progn (require (quote loaddefs-gen)) (loaddefs-generate default-directory "attest-autoloads.el"))'

clean:
	rm -f *.elc test/*.elc attest-autoloads.el
