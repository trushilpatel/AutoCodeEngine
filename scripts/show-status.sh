#!/usr/bin/env bash
# =============================================================================
# show-status.sh — Gate dashboard for a feature (or list all features)
#
# Usage:
#   bash scripts/show-status.sh features/<slug>/state.md       # single feature
#   bash scripts/show-status.sh --list features/               # all features
# =============================================================================

set -euo pipefail

# ── Locate repo root and load config ─────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/..")"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

[[ -f "$REPO_ROOT/.factory.env" ]] && source "$REPO_ROOT/.factory.env"

FEATURES_DIR="${FEATURES_DIR:-features}"

# ── Gate order (canonical pipeline sequence) ─────────────────────────────────
GATES=(prd_linter architect engineer qa ux performance cicd red_team push_to_pr)

declare -A GATE_LABELS=(
  [prd_linter]="PRD Linter"
  [architect]="Architect"
  [engineer]="Engineer"
  [qa]="QA"
  [ux]="UX"
  [performance]="Performance"
  [cicd]="CI/CD"
  [red_team]="Red Team"
  [push_to_pr]="Push-to-PR"
)

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

status_icon() {
  case "$1" in
    complete)         echo -e "${GREEN}✅ complete${NC}" ;;
    in_progress)      echo -e "${YELLOW}🔄 in_progress${NC}" ;;
    pending)          echo -e "${DIM}⬜ pending${NC}" ;;
    failed)           echo -e "${RED}❌ failed${NC}" ;;
    skipped)          echo -e "${DIM}⏭  skipped${NC}" ;;
    awaiting_human)   echo -e "${YELLOW}🧑 awaiting_human${NC}" ;;
    *)                echo -e "${DIM}— ${1:-unknown}${NC}" ;;
  esac
}

# ── Read a value from YAML state file via Python ──────────────────────────────
yaml_get() {
  local file="$1" key="$2" default="${3:-}"
  python3 - "$file" "$key" "$default" << 'PYEOF'
import sys, yaml
file, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    state = yaml.safe_load(open(file)) or {}
    keys = key.split(".")
    v = state
    for k in keys:
        v = v.get(k) if isinstance(v, dict) else None
        if v is None:
            break
    # Unwrap dicts that have a 'status' sub-key
    if isinstance(v, dict):
        v = v.get("status", default)
    print(v if v is not None else default)
except Exception:
    print(default)
PYEOF
}

# ── Single feature dashboard ──────────────────────────────────────────────────
show_feature() {
  local state_file="$1"

  if [[ ! -f "$state_file" ]]; then
    echo "State file not found: $state_file"
    echo "Run: make run FEATURE=<slug>"
    exit 1
  fi

  local slug;  slug=$(yaml_get "$state_file" "feature_slug" "unknown")
  local status; status=$(yaml_get "$state_file" "status" "unknown")
  local started; started=$(yaml_get "$state_file" "started_at" "")
  local updated; updated=$(yaml_get "$state_file" "updated_at" "")

  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  Feature: ${CYAN}${slug}${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  Overall status : $(status_icon "$status")"
  [[ -n "$started" ]] && echo -e "  Started        : ${DIM}${started}${NC}"
  [[ -n "$updated" ]] && echo -e "  Last updated   : ${DIM}${updated}${NC}"
  echo ""
  echo -e "  ${BOLD}Gate Pipeline${NC}"
  echo -e "  ─────────────────────────────────────────────"

  local all_complete=true
  local found_current=false

  for gate in "${GATES[@]}"; do
    local label="${GATE_LABELS[$gate]:-$gate}"
    local gstatus; gstatus=$(yaml_get "$state_file" "${gate}.status" "pending")
    local confidence; confidence=$(yaml_get "$state_file" "${gate}.confidence" "")
    local loopbacks; loopbacks=$(yaml_get "$state_file" "loop_backs.${gate}" "0")

    # Pad label to 14 chars
    local padded_label; padded_label=$(printf "%-14s" "$label")

    # Confidence suffix
    local conf_str=""
    if [[ -n "$confidence" && "$confidence" != "null" && "$confidence" != "None" ]]; then
      conf_str="  ${DIM}(conf: ${confidence})${NC}"
    fi

    # Loop-backs suffix
    local lb_str=""
    if [[ "$loopbacks" -gt 0 ]] 2>/dev/null; then
      lb_str="  ${YELLOW}[${loopbacks} loop-back(s)]${NC}"
    fi

    # Current gate marker
    local marker="  "
    if [[ "$gstatus" == "in_progress" || ("$gstatus" == "pending" && "$found_current" == "false" && "$all_complete" == "false") ]]; then
      marker="${CYAN}▶ ${NC}"
      found_current=true
    fi

    printf "  %b%-16s %b%b%b\n" "$marker" "$padded_label" "$(status_icon "$gstatus")" "$conf_str" "$lb_str"

    if [[ "$gstatus" != "complete" && "$gstatus" != "skipped" ]]; then
      all_complete=false
    fi
  done

  echo -e "  ─────────────────────────────────────────────"

  # Budget line (if .agent-calls exists)
  local feature_dir; feature_dir="$(dirname "$state_file")"
  local calls_file="$feature_dir/.agent-calls"
  if [[ -f "$calls_file" ]]; then
    local calls; calls=$(cat "$calls_file" 2>/dev/null || echo "0")
    local max="${MAX_AGENT_CALLS:-50}"
    local remaining=$(( max - calls ))
    local pct=$(( calls * 100 / max ))
    if (( remaining <= 5 )); then
      echo -e "  Agent calls    : ${RED}${calls} / ${max}${NC}  (${remaining} remaining — low!)"
    elif (( pct >= 60 )); then
      echo -e "  Agent calls    : ${YELLOW}${calls} / ${max}${NC}  (${remaining} remaining)"
    else
      echo -e "  Agent calls    : ${GREEN}${calls} / ${max}${NC}  (${remaining} remaining)"
    fi
  fi

  echo ""

  # Human action hint
  case "$status" in
    awaiting_human)
      echo -e "  ${YELLOW}⚠  Paused — human input needed.${NC}"
      echo -e "  ${DIM}Review state.md, resolve the blocker, then:${NC}"
      echo -e "  ${CYAN}  make resume FEATURE=${slug}${NC}"
      ;;
    complete)
      echo -e "  ${GREEN}🎉 Feature complete!${NC}"
      echo -e "  ${DIM}Run Steward to ingest learnings:  make steward FEATURE=${slug}${NC}"
      ;;
    in_progress)
      echo -e "  ${DIM}Loop is running. Nothing to do.${NC}"
      ;;
  esac

  echo ""
}

# ── List all features ─────────────────────────────────────────────────────────
list_features() {
  local features_dir="$1"

  if [[ ! -d "$features_dir" ]]; then
    echo "Features directory not found: $features_dir"
    exit 1
  fi

  echo ""
  echo -e "${BOLD}  All Features${NC}"
  echo -e "  ──────────────────────────────────────────────────────────────────"
  printf "  ${BOLD}%-24s %-18s %-10s %-10s${NC}\n" "Feature" "Status" "Calls" "Gates"
  echo -e "  ──────────────────────────────────────────────────────────────────"

  local found=false
  for state_file in "$features_dir"/*/state.md "$features_dir"/*/state.yaml; do
    [[ -f "$state_file" ]] || continue
    found=true

    local slug;   slug=$(yaml_get "$state_file" "feature_slug" "$(basename "$(dirname "$state_file")")")
    local status; status=$(yaml_get "$state_file" "status" "unknown")

    # Count completed gates
    local done_count=0
    for gate in "${GATES[@]}"; do
      local gs; gs=$(yaml_get "$state_file" "${gate}.status" "pending")
      [[ "$gs" == "complete" || "$gs" == "skipped" ]] && (( done_count++ )) || true
    done
    local total_gates=${#GATES[@]}

    # Agent calls
    local feature_dir; feature_dir="$(dirname "$state_file")"
    local calls="—"
    if [[ -f "$feature_dir/.agent-calls" ]]; then
      calls=$(cat "$feature_dir/.agent-calls" 2>/dev/null || echo "0")
      calls="${calls}/${MAX_AGENT_CALLS:-50}"
    fi

    # Colour status
    local status_col
    case "$status" in
      complete)        status_col="${GREEN}${status}${NC}" ;;
      awaiting_human)  status_col="${YELLOW}${status}${NC}" ;;
      in_progress)     status_col="${CYAN}${status}${NC}" ;;
      *)               status_col="${DIM}${status}${NC}" ;;
    esac

    printf "  %-24s " "$slug"
    printf "%b%-18s%b " "$status_col" "" "$NC"
    printf "%-10s " "$calls"
    printf "${DIM}%d / %d${NC}\n" "$done_count" "$total_gates"
  done

  if [[ "$found" == "false" ]]; then
    echo -e "  ${DIM}No features found. Create one with: make new FEATURE=<slug>${NC}"
  fi

  echo -e "  ──────────────────────────────────────────────────────────────────"
  echo ""
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--list" ]]; then
  list_features "${2:-$FEATURES_DIR}"
else
  show_feature "${1:-}"
fi
