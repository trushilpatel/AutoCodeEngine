#!/usr/bin/env bash
# =============================================================================
# show-budget.sh — Agent call budget for a feature
#
# Usage:
#   bash scripts/show-budget.sh features/<slug> [MAX_AGENT_CALLS]
#
# Called by: make budget FEATURE=<slug>
# =============================================================================

set -euo pipefail

# ── Locate repo root and load config ─────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/..")"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

[[ -f "$REPO_ROOT/.factory.env" ]] && source "$REPO_ROOT/.factory.env"

# ── Args ──────────────────────────────────────────────────────────────────────
FEATURE_DIR="${1:-}"
MAX="${2:-${MAX_AGENT_CALLS:-50}}"

if [[ -z "$FEATURE_DIR" ]]; then
  echo "Usage: make budget FEATURE=<slug>"
  exit 1
fi

# Normalise: strip trailing slash
FEATURE_DIR="${FEATURE_DIR%/}"
SLUG="$(basename "$FEATURE_DIR")"
CALLS_FILE="$FEATURE_DIR/.agent-calls"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# ── Read current count ────────────────────────────────────────────────────────
CALLS=0
if [[ -f "$CALLS_FILE" ]]; then
  CALLS=$(cat "$CALLS_FILE" 2>/dev/null || echo "0")
fi

REMAINING=$(( MAX - CALLS ))
PCT=$(( CALLS * 100 / MAX ))
BAR_FILL=$(( PCT * 30 / 100 ))
BAR_EMPTY=$(( 30 - BAR_FILL ))

# Build bar
BAR=""
for (( i=0; i<BAR_FILL; i++ )); do BAR+="█"; done
for (( i=0; i<BAR_EMPTY; i++ )); do BAR+="░"; done

# Colour threshold
if (( PCT >= 90 )); then
  BAR_COLOR="$RED"
elif (( PCT >= 60 )); then
  BAR_COLOR="$YELLOW"
else
  BAR_COLOR="$GREEN"
fi

# ── Output ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Budget: ${SLUG}${NC}"
echo -e "  ───────────────────────────────────────"
printf "  %b%s%b  %d / %d calls (%d%%)\n" \
  "$BAR_COLOR" "$BAR" "$NC" "$CALLS" "$MAX" "$PCT"
echo ""

if (( REMAINING < 0 )); then
  REMAINING=0
fi

echo -e "  Calls used    : ${BOLD}${CALLS}${NC}"
echo -e "  Calls allowed : ${DIM}${MAX}${NC}"

if (( REMAINING <= 0 )); then
  echo -e "  Remaining     : ${RED}0 — budget exhausted${NC}"
  echo ""
  echo -e "  ${YELLOW}The loop is paused. Increase MAX_AGENT_CALLS to resume:${NC}"
  echo -e "    make resume FEATURE=${SLUG} MAX_AGENT_CALLS=$(( MAX + 25 ))"
elif (( REMAINING <= 5 )); then
  echo -e "  Remaining     : ${RED}${REMAINING} — very low${NC}"
  echo ""
  echo -e "  ${YELLOW}Warning: nearly out of budget. To extend:${NC}"
  echo -e "    make resume FEATURE=${SLUG} MAX_AGENT_CALLS=$(( MAX + 25 ))"
elif (( PCT >= 60 )); then
  echo -e "  Remaining     : ${YELLOW}${REMAINING}${NC}"
else
  echo -e "  Remaining     : ${GREEN}${REMAINING}${NC}"
fi

echo -e "  ───────────────────────────────────────"
echo ""
