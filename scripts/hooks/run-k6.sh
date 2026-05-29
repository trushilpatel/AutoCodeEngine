#!/usr/bin/env bash
# run-k6.sh — Run k6 performance tests for a feature.
# Exit 0 = all thresholds met. Exit 1 = threshold breach.
#
# Usage:
#   ./scripts/hooks/run-k6.sh features/<slug>            # standard ramp test
#   ./scripts/hooks/run-k6.sh features/<slug> --mode=spike
#   ./scripts/hooks/run-k6.sh features/<slug> --mode=soak

set -euo pipefail

FEATURE_DIR="${1:-}"
MODE="${2:---mode=ramp}"

if [[ -z "$FEATURE_DIR" ]]; then
  echo "Usage: ./scripts/hooks/run-k6.sh features/<slug> [--mode=ramp|spike|soak]"
  exit 1
fi

if ! command -v k6 &>/dev/null; then
  echo "ERROR: k6 not installed. See https://k6.io/docs/getting-started/installation/"
  exit 1
fi

BASE_URL="${BASE_URL:-http://localhost:3000}"
SLUG="$(basename "$FEATURE_DIR")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Look for a feature-specific k6 script first, fall back to the generic pattern
K6_SCRIPT="$REPO_ROOT/scripts/hooks/k6-${SLUG}.js"
if [[ ! -f "$K6_SCRIPT" ]]; then
  # Use the mode-specific generic template from kb
  case "${MODE#--mode=}" in
    spike) K6_SCRIPT="$REPO_ROOT/scripts/hooks/k6-spike-generic.js" ;;
    soak)  K6_SCRIPT="$REPO_ROOT/scripts/hooks/k6-soak-generic.js" ;;
    *)     K6_SCRIPT="$REPO_ROOT/scripts/hooks/k6-ramp-generic.js" ;;
  esac
fi

if [[ ! -f "$K6_SCRIPT" ]]; then
  echo "ERROR: No k6 script found at $K6_SCRIPT"
  echo "Create one — see kb/performance/k6-patterns.md for templates."
  exit 1
fi

echo "[k6] Running ${MODE#--mode=} test for $SLUG against $BASE_URL"
echo "[k6] Script: $K6_SCRIPT"
echo ""

k6 run \
  --env BASE_URL="$BASE_URL" \
  --summary-export="$FEATURE_DIR/k6-results.json" \
  "$K6_SCRIPT"

EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
  echo "[k6] ✅ All thresholds met."
else
  echo "[k6] ❌ Threshold breach — performance gate FAILED."
fi

exit $EXIT_CODE
