#!/usr/bin/env bash
# =============================================================================
# run-steward.sh — Run the Steward after a feature merges (or on a weekly pass)
#
# Usage:
#   make steward FEATURE=<slug>   # post-merge KB ingestion
#   make steward-deep             # full hygiene pass (weekly)
#
# Direct:
#   bash scripts/run-steward.sh <slug>      # post-merge
#   bash scripts/run-steward.sh --full-pass # full hygiene
# =============================================================================

set -euo pipefail

# ── Locate repo root and load config ─────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/..")"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

[[ -f "$REPO_ROOT/.factory.env" ]] && source "$REPO_ROOT/.factory.env"

# ── Config (all overridable via .factory.env or CLI env) ─────────────────────
MODEL_HAIKU="${MODEL_HAIKU:-claude-haiku-4-5}"
FEATURES_DIR="${FEATURES_DIR:-features}"
KB_DIR="${KB_DIR:-kb}"
AGENTS_DIR="${AGENTS_DIR:-.claude/agents}"
TURNS_STEWARD="${TURNS_STEWARD:-15}"
TURNS_STEWARD_DEEP="${TURNS_STEWARD_DEEP:-30}"

# ── Max plan guard ────────────────────────────────────────────────────────────
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "ERROR: ANTHROPIC_API_KEY is set — this will bill the API, not your Max plan."
  echo "  Run:  unset ANTHROPIC_API_KEY  then re-authenticate:  claude login"
  exit 1
fi

# ── Dispatch ──────────────────────────────────────────────────────────────────
MODE="${1:-}"

if [[ "$MODE" == "--full-pass" ]]; then
  echo "[steward] Running full hygiene pass (deep mode)..."
  echo "[steward]   KB dir    : $KB_DIR"
  echo "[steward]   Agents dir: $AGENTS_DIR"
  echo "[steward]   Model     : $MODEL_HAIKU"
  echo "[steward]   Max turns : $TURNS_STEWARD_DEEP"
  echo ""

  claude -p "You are the Steward agent. Read your role definition at @${AGENTS_DIR}/steward.md.

Run a full deep hygiene pass:
- Step 2: KB hygiene — dedup, archive stale entries, flag contradictions.
- Step 3: Docs audit — check paths exist, Mermaid diagrams compile, add diagrams where only prose describes a process.
- Step 4: Agent file audit — verify all files in ${AGENTS_DIR}/ follow the canonical template.

KB directory: ${KB_DIR}/
Agents directory: ${AGENTS_DIR}/
Write proposals (not direct edits) for any agent file changes to: features/steward-proposals/

Report findings to: features/steward-$(date +%Y%m%d)/steward-report.md" \
    --model "$MODEL_HAIKU" \
    --max-turns "$TURNS_STEWARD_DEEP" \
    2>&1

  echo ""
  echo "[steward] Full hygiene pass complete."

else
  SLUG="$MODE"

  if [[ -z "$SLUG" ]]; then
    echo "Usage: make steward FEATURE=<slug>"
    echo "       make steward-deep"
    exit 1
  fi

  FEATURE_DIR="$REPO_ROOT/$FEATURES_DIR/$SLUG"

  if [[ ! -d "$FEATURE_DIR" ]]; then
    echo "ERROR: Feature directory not found: $FEATURE_DIR"
    exit 1
  fi

  # Find state file (may be .md or .yaml)
  STATE_FILE=""
  for ext in yaml md; do
    [[ -f "$FEATURE_DIR/state.$ext" ]] && STATE_FILE="$FEATURE_DIR/state.$ext" && break
  done

  echo "[steward] Ingesting learnings from feature: $SLUG"
  echo "[steward]   Feature dir: $FEATURE_DIR"
  echo "[steward]   KB dir     : $KB_DIR"
  echo "[steward]   Model      : $MODEL_HAIKU"
  echo "[steward]   Max turns  : $TURNS_STEWARD"
  echo ""

  STATE_REF=""
  [[ -n "$STATE_FILE" ]] && STATE_REF="State file: @${STATE_FILE}"

  claude -p "You are the Steward agent. Read your role definition at @${AGENTS_DIR}/steward.md.

The feature '${SLUG}' has just been merged.
Run Step 1 (post-feature KB ingestion) for this feature.

Feature folder: @${FEATURE_DIR}/
${STATE_REF}
Knowledge base index: @${KB_DIR}/INDEX.md

Promote generalizable learnings to the appropriate kb/ domain.
Update kb/INDEX.md after any additions." \
    --model "$MODEL_HAIKU" \
    --max-turns "$TURNS_STEWARD" \
    2>&1

  echo ""
  echo "[steward] Done. KB updated for: $SLUG"
fi
