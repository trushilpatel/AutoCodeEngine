#!/usr/bin/env bash
# run-tests.sh — Run the full test suite. Exit 0 = green. Exit 1 = red.
# Adapt the test command to your stack below.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "[tests] Running full test suite..."

# ── Adapt this section to your stack ─────────────────────────────────────────

# Node / Jest
if [[ -f "$REPO_ROOT/package.json" ]]; then
  cd "$REPO_ROOT"
  npx jest --passWithNoTests --forceExit 2>&1
  exit $?
fi

# Python / pytest
if [[ -f "$REPO_ROOT/pyproject.toml" || -f "$REPO_ROOT/setup.py" ]]; then
  cd "$REPO_ROOT"
  python -m pytest -x -q 2>&1
  exit $?
fi

# Go
if [[ -f "$REPO_ROOT/go.mod" ]]; then
  cd "$REPO_ROOT"
  go test ./... 2>&1
  exit $?
fi

# Ruby / RSpec
if [[ -f "$REPO_ROOT/Gemfile" ]]; then
  cd "$REPO_ROOT"
  bundle exec rspec --format progress 2>&1
  exit $?
fi

echo "WARNING: No recognised test runner found. Add your stack to scripts/hooks/run-tests.sh"
exit 1
