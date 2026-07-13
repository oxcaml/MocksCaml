# metrics-mock — prototype of a leaner metrics pipeline

This directory prototypes a revision to how OxCaml build/perf metrics get from
`oxcaml/oxcaml` into `oxcaml/oxcaml-metrics` (the CSV store + GitHub Pages
dashboard). It is a **mock**: the `push-metrics` job runs live against the
throwaway `oxcaml/MocksCaml-metrics` repo (set `env.METRICS_REPO`), never the
real `oxcaml/oxcaml-metrics`. `run-local.sh` here exercises the same logic fully
offline (no clone/push at all).

## The problem with the current setup

The metrics repo is used as a git-backed file store for raw data:

- On every push to `main`, the producer commits two raw files to `oxcaml-metrics`:
  `artifact-sizes-<date>-<sha>.csv` and `profiles-<date>-<sha>.tar.gz` (~3.5 MB).
- A second workflow in the metrics repo converts those into a small per-commit
  `data/metrics-<date>-<sha>.csv` (~40 rows) and commits *again*.

Measured on the live repo (2026-07): the checkout is **~1.84 GB** — ~1.86 GB of
`profiles-*.tar.gz` + ~274 MB of raw CSVs, versus **~3 MB** of `data/*.csv` that
the dashboard actually reads. Because the raw is committed to git, **every blob is
retained forever**; the producer's full clone re-downloads gigabytes each run, and
the two-commit producer→processor hand-off races (`git pull --rebase && git push`).

## What changes

Collapse to a single producer-side job and keep raw out of git history:

1. **Sparse, shallow clone** of `oxcaml-metrics` (`--depth 1`, `data/` + `scripts/`
   only) — no history, no raw.
2. **Convert in the producer**: run the metrics repo's `convert_metrics.py` on the
   freshly-built raw, writing the small per-commit `data/metrics-<date>-<sha>.csv`.
3. **Commit only `data/`** and push — one commit, no ping-pong. The second
   (processor) workflow in the metrics repo becomes deletable.
4. **Archive the raw to a monthly GitHub Release** (`gh release upload raw-YYYY-MM`)
   in the metrics repo — durable, browsable, downloadable, and **not in the git
   packfile**.

### Why keep the raw at all (and why Releases, not artifacts/cache)

The processed `data/*.csv` is **very lossy**: per-file artifact sizes collapse to
sums over 13 extensions, and the ~60+ compiler passes per module collapse to 6
hard-coded passes summed across all modules. Anything you'd want for a *better*
future analysis (a new pass, per-file regressions, distributions) is only
recoverable from the raw. So the raw must be retained durably.

That rules out short-lived **Actions artifacts** (≤90 days) and the **Actions
cache** (7-day eviction, 10 GB/repo cap, ephemeral by design — it would silently
delete the history we want). **Release assets** preserve everything today's git
history preserves, without the bloat. An external bucket (S3/R2) is an option only
if the raw archive grows large enough to warrant it.

## Files

- `convert_metrics.py` — verbatim copy of the converter from the metrics repo
  (`scripts/convert_metrics.py`). The live `push-metrics` job gets it from the
  sparse clone; this copy exists only so `run-local.sh` can run offline. Stdlib-only.
- `run-local.sh` — runs the whole revised flow offline against synthetic raw:
  convert → data-only commit (asserts no `raw-data/` leaks in) → prints the
  `gh release upload` dry-run commands. `bash tools/metrics-mock/run-local.sh`.

The corresponding live CI job is `push-metrics` in `.github/workflows/build.yml`.
It authenticates with a short-lived token minted by the metrics GitHub App
(`vars.APP_ID` + `secrets.PRIVATE_KEY`, set on the `metrics` environment),
sparse-clones `METRICS_REPO`, commits only `data/`, and archives the raw to a
monthly `raw-YYYY-MM` Release.

## Parity

`convert_metrics.py` run in the producer reproduces the two-stage pipeline's output
**byte-for-byte**. Verified against a real commit from the live repo
(`1f65e542`, 2026-07-13): re-converting its raw yielded a file identical to the
committed `data/metrics-2026-07-13-1f65e542.csv` (43 rows). So "process in the
producer" is behavior-preserving — only *where* the conversion runs changes.
