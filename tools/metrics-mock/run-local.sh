#!/usr/bin/env bash
# Local, offline exercise of the *revised* metrics pipeline (see README.md).
#
# It reproduces exactly what the `push-metrics` job in .github/workflows/build.yml
# does, minus the network:
#   1. take the raw metrics (artifact-sizes CSV + profiles tarball) the build leg
#      produced,
#   2. "sparse clone" the metrics repo (here: a local fixture with data/ + the
#      convert_metrics.py that lives in oxcaml/oxcaml-metrics),
#   3. run convert_metrics.py to fold the raw into a small per-commit CSV under
#      data/,
#   4. commit ONLY data/ (raw never enters the metrics git repo),
#   5. show the `gh release upload` commands that durably archive the raw.
#
# Run: bash tools/metrics-mock/run-local.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Pick python: prefer 3.12, fall back to python3.
PY="$(command -v python3.12 || command -v python3)"

DATE="2026-07-13"
HASH="deadbeef"                       # short hash for filenames
FULL_HASH="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
PR="1234"

# --- 1. synthesize the raw the build leg would hand off ------------------------
raw="$work/_metrics_output"
mkdir -p "$raw"

art="$raw/artifact-sizes-$DATE-$HASH.csv"
cat > "$art" <<EOF
timestamp,commit_hash,pr_number,kind,name,value
${DATE}T01:00:00Z,$FULL_HASH,$PR,size_in_bytes,bin/main.exe,12345678
${DATE}T01:00:00Z,$FULL_HASH,$PR,size_in_bytes,lib/foo.cmx,222222
${DATE}T01:00:00Z,$FULL_HASH,$PR,size_in_bytes,lib/foo.cmi,11111
${DATE}T01:00:00Z,$FULL_HASH,$PR,size_in_bytes,lib/foo.o,99999
EOF

# One synthetic profile CSV covering every KEY_PASS convert_metrics.py tracks.
prof_src="$work/_profile_csv"
mkdir -p "$prof_src"
cat > "$prof_src/profile.aaaaaa.csv" <<'EOF'
pass name,time,alloc,top-heap,absolute-top-heap,counters
file=test/foo.ml/,0.100s,10MB,2MB,8MB,
file=test/foo.ml//parsing,0.010s,1MB,0.5MB,6MB,
file=test/foo.ml//typing,0.020s,2MB,0.7MB,6.8MB,[comprehensions = 0]
file=test/foo.ml//generate/flambda2,0.030s,3MB,1MB,8MB,
file=test/foo.ml//generate/compile_phrases/cfg,0.025s,2.5MB,0.9MB,7.5MB,[reload = 5; spill = 3]
file=test/foo.ml//generate/assemble,0.015s,1.5MB,0.8MB,7MB,
EOF
tar czf "$raw/profiles-$DATE-$HASH.tar.gz" -C "$prof_src" .

echo "== raw handoff (would be an Actions artifact, ~days retention) =="
ls -la "$raw"

# --- 2. "sparse clone" of oxcaml-metrics (data/ + scripts/) -------------------
# In CI this is:  git clone --depth 1 --filter=blob:none --sparse \
#                   https://github.com/oxcaml/oxcaml-metrics && git sparse-checkout set data scripts
metrics="$work/metrics-repo"
mkdir -p "$metrics/scripts" "$metrics/data"
cp "$here/convert_metrics.py" "$metrics/scripts/convert_metrics.py"
git -C "$metrics" init -q -b main
git -C "$metrics" config user.name "github-actions[bot]"
git -C "$metrics" config user.email "github-actions[bot]@users.noreply.github.com"
git -C "$metrics" config commit.gpgsign false   # CI bot commits are unsigned
git -C "$metrics" add scripts/
git -C "$metrics" commit -q -m "seed: scripts + empty data (stand-in for sparse clone)"

# --- 3. convert raw -> small per-commit CSV under data/ -----------------------
"$PY" "$metrics/scripts/convert_metrics.py" \
  --artifact-sizes "$art" \
  --profiles "$raw/profiles-$DATE-$HASH.tar.gz" \
  --output-dir "$metrics/data"

out="$metrics/data/metrics-$DATE-$HASH.csv"
echo "== produced processed CSV =="
ls -la "$out"; echo "rows: $(($(wc -l < "$out") - 1))"; head -5 "$out"

# --- 4. commit ONLY data/ (raw never touches git) ----------------------------
git -C "$metrics" add data/
git -C "$metrics" commit -q -m "Add processed metrics for commit $FULL_HASH"
echo "== the single commit pushed to oxcaml-metrics (data-only) =="
git -C "$metrics" show --stat --oneline HEAD

# assertion: the commit must touch data/ only, never raw-data/
if git -C "$metrics" show --name-only --pretty=format: HEAD | grep -q '^raw-data/'; then
  echo "FAIL: commit contains raw-data/ — raw leaked into git!" >&2; exit 1
fi
echo "OK: commit is data-only; git history stays tiny."

# --- 5. durable raw archive via Release assets (dry run) ----------------------
month="${DATE%-*}"                    # e.g. 2026-07  -> monthly release bucket
echo "== durable raw archive (dry run) =="
echo "+ gh release create raw-$month --repo oxcaml/oxcaml-metrics \\"
echo "    --title 'Raw metrics $month' --notes 'Raw profiles + artifact sizes' || true"
echo "+ gh release upload raw-$month --repo oxcaml/oxcaml-metrics --clobber \\"
echo "    $raw/artifact-sizes-$DATE-$HASH.csv $raw/profiles-$DATE-$HASH.tar.gz"

echo
echo "ALL GOOD ✅  (processed CSV committed; raw archived to a Release; no git bloat)"
