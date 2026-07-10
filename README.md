# MocksCaml

A mock repo for testing [oxcaml](https://github.com/oxcaml/oxcaml)'s
GitHub CI machinery — triggers, permissions, deployment environments and
secret gating, artifacts, matrix builds, PR labels, merge queue,
dependabot, SARIF upload — without building a real compiler.

The workflows in `.github/workflows/` are trimmed copies of oxcaml's. The
"compiler" they build is a hello-world compiled with a stock `ocamlopt`,
behind an autoconf + `make` skeleton whose command shape mirrors oxcaml
CI:

```
autoconf
./configure --prefix=... $MATRIX_CONFIG
make compiler test install
```

## What's mocked vs. real

| Piece | Status |
| --- | --- |
| `build.yml` | Real workflow structure; matrix trimmed 28 → 5 legs; GitHub-hosted runners instead of WarpBuild |
| `push-metrics` job | Identical (environment `metrics`, `METRICS_REPO_TOKEN`, artifact handoff) except the final `git push` is a **dry run** |
| `ocaml/setup-ocaml` + `tools/ci/local-opam` | Real; the `oxcaml-ci-deps` meta-package (same name/version) depends on just a stock `ocaml-base-compiler.5.4.0` |
| `scripts/collect-metrics.py` | Verbatim copy from oxcaml |
| `ocamlformat.yml` | Real label plumbing (`skip 80ch`, incl. merge-queue path); `dune build @fmt` replaced by a tabs/trailing-whitespace check; `scripts/80ch.sh` is oxcaml's minus the ocamlformat bits |
| `zizmor.yml`, `document-syntax.yml`, `tsan.yml`, `dependabot.yml` | Verbatim copies |
| `nix-github-actions.yml` | Real dynamic-matrix + trusted/untrusted cachix split; `flake.nix` hand-rolls the `githubActions.matrix` attrset; cache renamed `mockscaml`. No `flake.lock` is committed — the single input is pinned by commit hash and CI resolves it on the fly |
| `default.nix` | Same shape as oxcaml's (feature flags → `configureFlags`, boot OCaml 5.4.0 built via nixpkgs' `generic.nix`, `autoconf`/`configure`/`make`/`make test`), building the mock instead of a compiler |
| The compiler | `src/hello.ml` |

