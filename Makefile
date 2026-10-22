# fab-lang: one entry point for the whole monorepo.
#
#   make              build everything (debug)
#   make test         run every package's tests, in dependency order
#   make install      install `fab` (release) into $(PREFIX)/bin
#
# Each package is a plain Zig project; this file only calls `zig build` in
# each one, in dependency order: fab-core, then fab-render, then fab-cli.
#
# Variables:
#   ZIG       the Zig 0.17 compiler          (default: zig)
#   PREFIX    where `install` puts bin/fab   (default: ~/.local)
#   OPTIMIZE  optimize mode for `install`    (default: ReleaseSafe)
#
# Examples:
#   make install PREFIX=/usr/local      (may need sudo)
#   make test ZIG=~/zig-0.17/zig

ZIG      ?= zig
PREFIX   ?= $(HOME)/.local
OPTIMIZE ?= ReleaseSafe

# In dependency order.
PACKAGES := fab-core fab-render fab-cli

.PHONY: all build test test-core test-render test-cli \
        release install uninstall fmt fmt-check check-graphviz clean help

all: build

help:
	@sed -n '2,/^$$/p' $(firstword $(MAKEFILE_LIST)) | sed 's/^# \{0,1\}//'
	@echo "Targets: build test test-core test-render test-cli release install"
	@echo "         uninstall fmt fmt-check check-graphviz clean help"

## Building

build:
	@for p in $(PACKAGES); do \
		echo "==> build $$p"; \
		(cd $$p && $(ZIG) build) || exit 1; \
	done

## Testing

test: test-core test-render test-cli

test-core:
	@echo "==> test fab-core"
	@cd fab-core && $(ZIG) build test --summary all

test-render:
	@echo "==> test fab-render"
	@cd fab-render && $(ZIG) build test --summary all

test-cli:
	@echo "==> test fab-cli"
	@cd fab-cli && $(ZIG) build test --summary all

## Installing fab

# A release build of fab into fab-cli/zig-out/bin, without installing it.
release:
	@echo "==> release fab ($(OPTIMIZE))"
	@cd fab-cli && $(ZIG) build -Doptimize=$(OPTIMIZE)

# Tests first, so a broken fab is never installed.
install: test
	@echo "==> install fab into $(PREFIX)/bin"
	@cd fab-cli && $(ZIG) build -Doptimize=$(OPTIMIZE) --prefix "$(abspath $(PREFIX))"
	@echo "installed: $(PREFIX)/bin/fab"
	@case ":$$PATH:" in *":$(abspath $(PREFIX))/bin:"*) ;; \
		*) echo "note: $(PREFIX)/bin is not on your PATH";; esac
	@$(MAKE) --no-print-directory check-graphviz

uninstall:
	@rm -f "$(PREFIX)/bin/fab" && echo "removed: $(PREFIX)/bin/fab"

# `fab render -e graphviz` to svg, png or pdf needs `dot`; `-f dot` doesn't.
check-graphviz:
	@command -v dot >/dev/null 2>&1 \
		&& echo "graphviz: $$(dot -V 2>&1)" \
		|| echo "note: Graphviz not found; \`-e graphviz\` can only write \`-f dot\` (https://graphviz.org/download)"

## Housekeeping

fmt:
	@for p in $(PACKAGES); do \
		(cd $$p && $(ZIG) fmt build.zig src $$( [ -d test ] && echo test )) || exit 1; \
	done

fmt-check:
	@for p in $(PACKAGES); do \
		(cd $$p && $(ZIG) fmt --check build.zig src $$( [ -d test ] && echo test )) || exit 1; \
	done

clean:
	@for p in $(PACKAGES); do \
		echo "==> clean $$p"; \
		rm -rf $$p/.zig-cache $$p/zig-out; \
	done
