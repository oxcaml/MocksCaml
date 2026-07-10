#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

# Mock stand-in for oxcaml's dune/ocamlformat-based scripts/fmt.sh: fix what
# tools/ci/actions/check-fmt.sh flags, i.e. tabs and trailing whitespace in
# tracked OCaml sources.
git ls-files -z -- '*.ml' '*.mli' '*.mly' | while IFS= read -r -d '' f; do
  perl -pi -e 's/[ \t]+$//; s/\t/  /g' "$f"
done
