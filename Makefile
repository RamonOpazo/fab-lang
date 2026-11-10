# fab-lang: one entry point for the whole monorepo.
#
#   make              build everything (debug)
#   make test         run every package's tests, in dependency order
#   make examples     check every example, then draw it to SVG (Graphviz)
#   make install      install `fab` (release) into $(PREFIX)/bin
#   make test-tree-sitter   the editors' grammar (needs Node; not in `test`)
#   make fmt          format the Zig sources, the examples and the prelude
#   make fmt-check    check they are formatted (zig fmt, then `fab fmt`)
#
# Each package is a plain Zig project; this file only calls `zig build` in
# each one, in dependency order: fab-core, then fab-render and fab-lsp, then
# fab-cli.
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
PACKAGES := fab-core fab-render fab-lsp fab-cli

.PHONY: all build test test-versions test-core test-render test-lsp test-cli examples \
        tree-sitter test-tree-sitter release install uninstall fmt fmt-check check-graphviz clean help

all: build

help:
	@sed -n '2,/^$$/p' $(firstword $(MAKEFILE_LIST)) | sed 's/^# \{0,1\}//'
	@echo "Targets: build test test-versions test-core test-render test-lsp test-cli examples release install"
	@echo "         tree-sitter test-tree-sitter uninstall fmt fmt-check check-graphviz clean help"

## Building

build:
	@for p in $(PACKAGES); do \
		echo "==> build $$p"; \
		(cd $$p && $(ZIG) build) || exit 1; \
	done

## Testing

test: test-versions test-core test-render test-lsp test-cli

# One version, written once (release.md §3): fab-core's manifest holds it,
# and Zig wants it in the other three too, so they must say the same.
test-versions:
	@echo "==> test versions"
	@want=$$(sed -n 's/^ *\.version = "\(.*\)",$$/\1/p' fab-core/build.zig.zon); \
	for p in $(PACKAGES); do \
		got=$$(sed -n 's/^ *\.version = "\(.*\)",$$/\1/p' $$p/build.zig.zon); \
		[ "$$got" = "$$want" ] || { echo "$$p/build.zig.zon: version $$got, but fab-core's is $$want"; exit 1; }; \
	done; echo "all at $$want"

test-core:
	@echo "==> test fab-core"
	@cd fab-core && $(ZIG) build test --summary all

test-render:
	@echo "==> test fab-render"
	@cd fab-render && $(ZIG) build test --summary all

test-lsp:
	@echo "==> test fab-lsp"
	@cd fab-lsp && $(ZIG) build test --summary all

test-cli:
	@echo "==> test fab-cli"
	@cd fab-cli && $(ZIG) build test --summary all

## Examples

FAB      := fab-cli/zig-out/bin/fab
EXAMPLES := $(wildcard examples/*.fab)

# Each example must check with no error and no warning (`--strict`;
# unsupported is allowed), and is then drawn to SVG beside it. Every example
# is checked before any is drawn. `make test examples` runs both.
examples: build
	@command -v dot >/dev/null 2>&1 || { echo "error: \`make examples\` draws with Graphviz, which is not installed"; exit 1; }
	@echo "==> check examples"
	@for f in $(EXAMPLES); do \
		$(FAB) check "$$f" --strict --no-color >/dev/null 2>&1 \
			|| { echo "error: $$f does not check:"; $(FAB) check "$$f" --strict --no-color; exit 1; }; \
	done
	@echo "==> draw examples"
	@for f in $(EXAMPLES); do \
		$(FAB) render "$$f" -e graphviz -f svg --verbosity quiet || exit 1; \
		echo "    $${f%.fab}.svg"; \
	done

## The editors' grammar

# tree-sitter-fab is outside fAB: it needs Node and the Tree-sitter CLI, so
# `make test` never runs it, and without npm these targets only say so.
# npm no longer runs install scripts, so the CLI's binary is fetched by hand.
TS_DIR := tree-sitter-fab
TS     := node_modules/.bin/tree-sitter

tree-sitter:
	@command -v npm >/dev/null 2>&1 || { echo "skip: tree-sitter-fab needs Node (npm)"; exit 0; }; \
	cd $(TS_DIR) && { [ -x node_modules/tree-sitter-cli/tree-sitter ] \
		|| { npm ci --no-audit --no-fund --silent && node node_modules/tree-sitter-cli/install.js; }; } \
	&& $(TS) generate && echo "==> generated $(TS_DIR)/src"

test-tree-sitter: tree-sitter
	@command -v npm >/dev/null 2>&1 || exit 0; \
	echo "==> test tree-sitter-fab"; \
	cd $(TS_DIR) && $(TS) test && $(TS) parse -q -s $(addprefix ../,$(EXAMPLES)) ../fab-core/src/prelude.fab

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

# The fAB sources: the examples and the prelude, formatted by `fab fmt`.
FAB_SOURCES := $(EXAMPLES) fab-core/src/prelude.fab

fmt: build
	@for p in $(PACKAGES); do \
		(cd $$p && $(ZIG) fmt build.zig src $$( [ -d test ] && echo test )) || exit 1; \
	done
	@for f in $(FAB_SOURCES); do $(FAB) fmt -w "$$f" || exit 1; done

fmt-check: build
	@for p in $(PACKAGES); do \
		(cd $$p && $(ZIG) fmt --check build.zig src $$( [ -d test ] && echo test )) || exit 1; \
	done
	@status=0; for f in $(FAB_SOURCES); do $(FAB) fmt --check "$$f" || status=1; done; exit $$status

clean:
	@for p in $(PACKAGES); do \
		echo "==> clean $$p"; \
		rm -rf $$p/.zig-cache $$p/zig-out; \
	done
