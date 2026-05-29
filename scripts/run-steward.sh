#!/usr/bin/env bash
# =============================================================================
# run-steward.sh — Run the Steward after a feature merges (or on a weekly pass)
#
# Two-tier KB:
#   KB_DIR        — project KB at repo root (committed to your project)
#   ENGINE_KB_DIR — engine KB inside AutoCodeEngine (shared across all projects)
#
# Steward classifies each learning:
#   Project-specific  → writes to KB_DIR/
#   Generalizable     → writes proposal to ENGINE_KB_DIR/proposals/ for human PR
#
# Usage:
#   make steward FEATURE=<slug>   # post-merge KB ingestion
#   make steward-deep             # full hygiene pass on both KBs (weekly)
# =============================================================================

set -euo pipefail

# ── Locate repo root and load config ─────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/..")"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

[[ -f "$REPO_ROOT/.factory.env" ]] && source "$REPO_ROOT/.factory.env"

# ── Config ────────────────────────────────────────────────────────────────────
MODEL_HAIKU="${MODEL_HAIKU:-claude-haiku-4-5}"
FEATURES_DIR="${FEATURES_DIR:-features}"
KB_DIR="${KB_DIR:-kb}"
AGENTS_DIR="${AGENTS_DIR:-.claude/agents}"
TURNS_STEWARD="${TURNS_STEWARD:-15}"
TURNS_STEWARD_DEEP="${TURNS_STEWARD_DEEP:-30}"

# ENGINE_KB_DIR: auto-detect from script location (inside AutoCodeEngine/scripts/)
# The engine KB lives one level up from scripts/ inside the AutoCodeEngine dir.
_ENGINE_DEFAULT="$(cd "$SCRIPT_DIR/.." && pwd)/kb"
ENGINE_KB_DIR="${ENGINE_KB_DIR:-$_ENGINE_DEFAULT}"

# ── Max plan guard ────────────────────────────────────────────────────────────
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "ERROR: ANTHROPIC_API_KEY is set — this will bill the API, not your Max plan."
  echo "  Run:  unset ANTHROPIC_API_KEY  then re-authenticate:  claude login"
  exit 1
fi

# ── Ensure engine KB proposals dir exists ────────────────────────────────────
mkdir -p "$ENGINE_KB_DIR/proposals"

# ── Dispatch ──────────────────────────────────────────────────────────────────
MODE="${1:-}"

if [[ "$MODE" == "--full-pass" ]]; then
  echo "[steward] Running full hygiene pass (both KBs)..."
  echo "[steward]   Project KB : $KB_DIR"
  echo "[steward]   Engine KB  : $ENGINE_KB_DIR"
  echo "[steward]   Agents dir : $AGENTS_DIR"
  echo "[steward]   Model      : $MODEL_HAIKU"
  echo "[steward]   Max turns  : $TURNS_STEWARD_DEEP"
  echo ""

  claude -p "You are the Steward agent. Read your role definition at @${AGENTS_DIR}/steward.md.

Run a full deep hygiene pass across both knowledge bases.

## KB directories
Project KB (project-specific, committed to this repo): ${KB_DIR}/
Engine KB (generalizable, shared across all projects):  ${ENGINE_KB_DIR}/

## Tasks
Step 2: KB hygiene on both KBs
  - Find duplicates, keep more complete entry, archive the other
  - Archive stale entries to ${KB_DIR}/archive/
  - Flag contradictions for human resolution

Step 3: Docs audit (docs/ directory)
  - Check all referenced paths exist
  - Verify Mermaid diagrams compile: mmdc -i <file> -o /tmp/test.svg 2>&1
  - Add diagrams where only prose describes a process

Step 4: Agent file audit
  - Verify all files in ${AGENTS_DIR}/ have required frontmatter + sections
  - Write proposed fixes to: features/steward-proposals/ (do not auto-apply)

Report all findings to: features/steward-$(date +%Y%m%d)/steward-report.md" \
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

  # Find state file
  STATE_FILE=""
  for ext in yaml md; do
    [[ -f "$FEATURE_DIR/state.$ext" ]] && STATE_FILE="$FEATURE_DIR/state.$ext" && break
  done

  echo "[steward] Ingesting learnings from feature: $SLUG"
  echo "[steward]   Feature dir : $FEATURE_DIR"
  echo "[steward]   Project KB  : $KB_DIR"
  echo "[steward]   Engine KB   : $ENGINE_KB_DIR"
  echo "[steward]   Model       : $MODEL_HAIKU"
  echo "[steward]   Max turns   : $TURNS_STEWARD"
  echo ""

  STATE_REF=""
  [[ -n "$STATE_FILE" ]] && STATE_REF="State file: @${STATE_FILE}"

  claude -p "You are the Steward agent. Read your role definition at @${AGENTS_DIR}/steward.md.

The feature '${SLUG}' has just been merged. Run Step 1: post-merge KB ingestion.

## Feature to ingest
Feature folder: @${FEATURE_DIR}/
${STATE_REF}

## Two-tier KB — route each learning correctly

**Project KB** (write directly): ${KB_DIR}/
  For: codebase-specific patterns, team decisions, stack quirks for THIS project
  Update: ${KB_DIR}/INDEX.md after adding entries

**Engine KB proposals** (write proposal file, do NOT edit engine KB directly): ${ENGINE_KB_DIR}/proposals/
  For: learnings that would help developers on any other codebase
  File naming: ${ENGINE_KB_DIR}/proposals/$(date +%Y-%m-%d)_${SLUG}_<topic>.md
  Each proposal must include a 'Why engine-level:' rationale line

## Classification rule
Ask: 'Would a developer on a completely different codebase benefit from this?'
  Yes → Engine KB proposal
  No  → Project KB (direct write)
  Uncertain → Project KB (err on the side of not polluting the engine KB)

Engine KB proposals will be reviewed by a human before being merged into AutoCodeEngine." \
    --model "$MODEL_HAIKU" \
    --max-turns "$TURNS_STEWARD" \
    2>&1

  echo ""

  # Report any proposals created
  PROPOSALS=$(find "$ENGINE_KB_DIR/proposals" -name "$(date +%Y-%m-%d)_${SLUG}*" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$PROPOSALS" -gt 0 ]]; then
    echo "[steward] ✅ Project KB updated."
    echo "[steward] 📋 $PROPOSALS engine KB proposal(s) written to: $ENGINE_KB_DIR/proposals/"
    echo "[steward]    Review and open a PR to AutoCodeEngine to share with all projects."
    find "$ENGINE_KB_DIR/proposals" -name "$(date +%Y-%m-%d)_${SLUG}*" | while read -r f; do
      echo "[steward]    → $(basename "$f")"
    done
  else
    echo "[steward] ✅ Project KB updated. No engine-level learnings identified."
  fi
  echo ""
fi
