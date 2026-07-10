# Local Opam Repository

This is a local Opam repository mirroring the one in oxcaml, so that the
`ocaml/setup-ocaml` workflow step can be exercised unchanged in MocksCaml.

## Purpose

In oxcaml, this repository carries a patched OCaml compiler and a CI
dependencies meta-package. Here it carries only the `oxcaml-ci-deps`
meta-package (same name and version as oxcaml's, so the workflow step is
byte-identical), trimmed to depend on just a stock `ocaml-base-compiler`
from the default opam repository.
