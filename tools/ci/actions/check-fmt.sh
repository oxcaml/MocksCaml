#!/usr/bin/env bash

#**************************************************************************#
#*                                                                        *#
#*                                 OCaml                                  *#
#*                                                                        *#
#*                  Jacob Van Buren, Jane Street, New York                *#
#*                                                                        *#
#*   Copyright 2025 Jane Street Group LLC                                 *#
#*                                                                        *#
#*   All rights reserved.  This file is distributed under the terms of    *#
#*   the GNU Lesser General Public License version 2.1, with the          *#
#*   special exception on linking described in the file LICENSE.          *#
#*                                                                        *#
#**************************************************************************#

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

exit_code=0
# Mock stand-in for oxcaml's `dune build @fmt`: tracked OCaml sources must
# not contain tabs or trailing whitespace.
if git grep -nEI $'\t|[ \t]+$' -- '*.ml' '*.mli' '*.mly'; then
  echo "error: mock formatting check failed (tabs or trailing whitespace)" >&2
  exit_code=1
fi
if [[ -z "${SKIP_80CH+x}" ]]; then # don't use `-v` to accommodate macOS (old bash)
  scripts/80ch.sh || exit_code=1
fi
exit $exit_code
