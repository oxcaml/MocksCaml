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
# if OCAMLPARAM carries a dump-dir, drop a profile CSV there for
# scripts/collect-metrics.py to archive. The schema must match what
# oxcaml-metrics' convert_metrics.py expects
# (pass name,time,alloc,top-heap,absolute-top-heap,counters with file=..//pass
# rows), so emit a minimal one covering the KEY_PASSES it tracks.
.PHONY: compiler
compiler:
	@echo "BUILD_OCAMLPARAM=$$BUILD_OCAMLPARAM"
	@echo "OCAMLPARAM=$$OCAMLPARAM OCAMLRUNPARAM=$$OCAMLRUNPARAM USE_RUNTIME=$$USE_RUNTIME"
	mkdir -p $(BUILD)
	cd src && $(OCAMLOPT) -o ../$(BUILD)/hello hello.ml
	$(BUILD)/hello
	@dump_dir=$$(printf '%s' "$$OCAMLPARAM" | tr ',' '\n' | sed -n 's/^dump-dir=//p' | tail -n 1); \
	if [ -n "$$dump_dir" ] && [ -d "$$dump_dir" ]; then \
	  printf '%s\n' \
	    'pass name,time,alloc,top-heap,absolute-top-heap,counters' \
	    'file=src/hello.ml/,0.042s,10MB,2MB,8MB,' \
	    'file=src/hello.ml//parsing,0.001s,1MB,0.5MB,6MB,' \
	    'file=src/hello.ml//typing,0.002s,2MB,0.7MB,6.8MB,' \
	    'file=src/hello.ml//generate/flambda2,0.003s,3MB,1MB,8MB,' \
	    'file=src/hello.ml//generate/compile_phrases/cfg,0.002s,2.5MB,0.9MB,7.5MB,[reload = 5; spill = 3]' \
	    'file=src/hello.ml//generate/assemble,0.001s,1.5MB,0.8MB,7MB,' \
	    > "$$dump_dir/profile.compiler.$$$$.csv"; \
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
