# Mock stand-in for oxcaml's Makefile: exposes the targets that GitHub CI
# drives (compiler, test, install, promote-failed) but builds a
# hello-world instead of a compiler.

# fmt/check-fmt work in an unconfigured tree; everything else needs
# `autoconf && ./configure` first.
ifeq (,$(wildcard Makefile.config))
  ifneq (,$(filter-out fmt check-fmt,$(or $(MAKECMDGOALS),compiler)))
    $(error Makefile.config not found: run `autoconf && ./configure` first)
  endif
else
  include Makefile.config
endif

BUILD = _build

# The last recipe line mimics oxcaml's profile=1,dump-into-csv=1 pipeline:
# if OCAMLPARAM carries a dump-dir, drop a plausible profile CSV there for
# scripts/collect-metrics.py to archive.
.PHONY: compiler
compiler:
	@echo "BUILD_OCAMLPARAM=$$BUILD_OCAMLPARAM"
	@echo "OCAMLPARAM=$$OCAMLPARAM OCAMLRUNPARAM=$$OCAMLRUNPARAM USE_RUNTIME=$$USE_RUNTIME"
	mkdir -p $(BUILD)
	cd src && $(OCAMLOPT) -o ../$(BUILD)/hello hello.ml
	$(BUILD)/hello
	@dump_dir=$$(printf '%s' "$$OCAMLPARAM" | tr ',' '\n' | sed -n 's/^dump-dir=//p' | tail -n 1); \
	if [ -n "$$dump_dir" ] && [ -d "$$dump_dir" ]; then \
	  printf 'pass,elapsed_s\ncompiler,0.042\n' > "$$dump_dir/profile.compiler.$$$$.csv"; \
	fi

# The entire testsuite: run hello and diff its output against the reference.
.PHONY: test
test: compiler
	$(BUILD)/hello > $(BUILD)/hello.output
	diff -u test/hello.reference $(BUILD)/hello.output

.PHONY: fmt
fmt:
	bash scripts/fmt.sh

.PHONY: check-fmt
check-fmt:
	bash tools/ci/actions/check-fmt.sh

.PHONY: install
install: compiler
	mkdir -p "$(prefix)/bin" "$(prefix)/lib/mockscaml"
	install $(BUILD)/hello "$(prefix)/bin/hello"
	install -m 644 src/hello.cmi src/hello.cmx src/hello.o \
	  "$(prefix)/lib/mockscaml/"

# Overwrite the reference with the actual output so `git diff` shows the
# failure (the workflow uploads that diff as the test-diffs artifact).
.PHONY: promote-failed
promote-failed:
	@if [ -f $(BUILD)/hello.output ] \
	  && ! cmp -s $(BUILD)/hello.output test/hello.reference; then \
	  cp $(BUILD)/hello.output test/hello.reference; \
	  echo "promoted test/hello.reference"; \
	fi
