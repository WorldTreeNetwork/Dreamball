#!/usr/bin/env bash
# scripts/perf/embedding.sh — K-NN perf gate (S6.3 AC3 / R5 mitigation)
#
# Drives the kNN perf test with a deterministic 500-inscription corpus.
# Measures ONLY the query-embed round-trip + kNN Cypher (NOT corpus setup).
#
# Gates:
#   p50 <200ms — HARD gate: exit 1 on breach.
#   p95 <400ms — SOFT ceiling: warns + suggests ADR addendum; does NOT exit 1.
#
# Output:
#   budget-met             — p50 <200ms (and p95 < 400ms)
#   warn-threshold-near-budget — p50 <200ms but p95 in [200ms, 400ms)
#   HARD BLOCK             — p50 >= 200ms (exits 1)
#
# Usage:
#   bash scripts/perf/embedding.sh
#   SKIP_PERF=1 bash scripts/perf/embedding.sh   # skip (CI fast path)
#
# Requires: bun, jelly-server not needed (JELLY_EMBED_MOCK=1 activates mock).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [ "${SKIP_PERF:-0}" = "1" ]; then
  echo "SKIP_PERF=1 — skipping perf gate"
  echo "budget-met (skipped)"
  exit 0
fi

echo "=== S6.3 K-NN perf gate (R5 mitigation) ==="
echo "Corpus: 500 inscriptions, 256d embeddings (pre-populated, no Qwen3)"
echo "Budget: p50 <200ms (hard), p95 <400ms (soft)"
echo ""

# Run the dedicated perf runner script via bun
PERF_OUT=$(JELLY_EMBED_MOCK=1 bun run --silent "${REPO_ROOT}/scripts/perf/run-knn-perf.ts" 2>&1)
EXIT_CODE=$?

echo "$PERF_OUT"

if [ $EXIT_CODE -ne 0 ]; then
  echo ""
  echo "HARD BLOCK: K-NN p50 >= 200ms — S6.3 R5 mitigation FAILED"
  echo "Action: Profile the kNN path. See docs/known-gaps.md for ADR addendum procedure."
  exit 1
fi

# Parse output for warn condition
if echo "$PERF_OUT" | grep -q "warn-threshold-near-budget"; then
  echo ""
  echo "warn-threshold-near-budget"
  echo "Note: p95 in [200ms, 400ms) soft zone. Consider:"
  echo "  1. Adding an ADR addendum to docs/decisions/ documenting measured numbers."
  echo "  2. Profiling upsertEmbedding batch vs individual insert pattern."
  exit 0
fi

echo ""
echo "budget-met"
