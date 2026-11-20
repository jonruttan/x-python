# x-python -- the Python lang for x-lang
#
#   make test          the bundle's own spec suite
#   make test-boot     one program through `x -l python`, on the declared dialect
#   make conformance   score against the MicroPython-derived suite
#   make install       into the x on PATH
#
# INSTALL PUTS THIS BUNDLE WHERE `-l` LOOKS, which is the whole of it: an
# installed x searches <share>/langs/*/lang.xon, so a lang is "installed" when
# its files are there.  Use lang.pin.xon and `Pin bundle` instead when it
# matters to a build which version it got.

X ?= x
SHARE := $(if $(PREFIX),$(PREFIX)/share/x,$(shell $(X) --share-dir))
DEST  := $(SHARE)/langs/python

# What a consumer needs to RUN the lang.  Not the suite, not the tooling.
PAYLOAD := lang.xon run.x python

.PHONY: install
install: ## Install into <share>/langs/python
	@test -n "$(SHARE)" || { echo "x-python: cannot find an x tree -- set PREFIX or X" >&2; exit 1; }
	@test -d "$(SHARE)" || { echo "x-python: no x tree at $(SHARE)" >&2; exit 1; }
	rm -rf "$(DEST)"
	mkdir -p "$(DEST)"
	cp -R $(PAYLOAD) "$(DEST)/"
	@echo "x-python: installed to $(DEST)"
	@echo "x-python: writing the boot image"
	"$(X)" --image -l python || true
	@echo "x-python: try  x -l python"

.PHONY: uninstall
uninstall: ## Remove it again
	rm -rf "$(DEST)"
	@echo "x-python: removed $(DEST)"

.PHONY: test
test: ## Run the bundle's own spec suite
	X="$(X)" sh tests/spec-runner.sh

.PHONY: test-boot
test-boot: ## Run a program through `x -l python`, on the declared dialect
	X="$(X)" sh tests/boot.sh

# The card runs from here, so X is an installed x: a checkout's wrapper runs
# only from its own root.  X_LANG_DIR is the directory holding this bundle,
# so `x -l python` loads this tree and not an installed copy.  CARD_SH is the
# check: the installed x-lang's, or a newer one named here.
.PHONY: card
card: ## Hold docs/card.md to the card format and run its programs
	X_LANG_DIR="$${X_LANG_DIR:-$(CURDIR)/..}" BUNDLE=. X="$(X)" \
		sh "$${CARD_SH:-$$("$(X)" --share-dir)/tools/lang-kit/card.sh}"

.PHONY: fetch
fetch: ## Fetch and verify the pinned upstream test corpus
	sh tools/conformance/fetch.sh

.PHONY: gen
gen: fetch ## Generate tests/conformance/*.spec.md from the corpus
	sh tools/conformance/gen-specs.sh

.PHONY: conformance
conformance: gen ## Run the generated conformance suite, case by case
	X="$(X)" SPEC_PATH="$(CURDIR)/tests/conformance" sh tests/spec-runner.sh

.PHONY: score
score: ## Conformance pass/total per group, worst first
	X="$(X)" sh tools/conformance/score.sh

.PHONY: bundle
bundle: ## Roll a release tarball and print its pin
	sh tools/bundle.sh

.PHONY: clean
clean: ## Drop everything generated
	rm -rf tests/lib tests/conformance deps

.PHONY: help
help: ## Show targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[32m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
