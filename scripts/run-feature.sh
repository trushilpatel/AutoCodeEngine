#!/usr/bin/env bash
# =============================================================================
# run-feature.sh — AI Dev Factory Orchestrator
#
# Normally called via Makefile:
#   make run    FEATURE=my-feature
#   make resume FEATURE=my-feature
#
# Direct usage:
#   ./scripts/run-feature.sh features/<slug>/PRD.md
#   ./scripts/run-feature.sh features/<slug>/state.md --resume
#
# All configuration lives in .factory.env (gitignored).
# Copy .factory.env.example → .factory.env to customise.
# Every variable can also be overridden as an environment variable or
# via the Makefile: make run FEATURE=foo MAX_AGENT_CALLS=30
# =============================================================================

set -euo pipefail

# ── Safety: API key must be unset to use Max plan ────────────────────────────
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "ERROR: ANTHROPIC_API_KEY is set. This will bill the API, not your Max plan."
  echo "  Run: unset ANTHROPIC_API_KEY"
  exit 1
fi

# ── Load config (Makefile exports these; direct callers need .factory.env) ────
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || cd "$(dirname "$0")/.." && pwd)"
[[ -f "$REPO_ROOT/.factory.env" ]] && source "$REPO_ROOT/.factory.env"

# ── Configuration — all variables have safe defaults ──────────────────────────
MODEL_HAIKU="${MODEL_HAIKU:-claude-haiku-4-5}"
MODEL_SONNET="${MODEL_SONNET:-claude-sonnet-4-5}"
MODEL_OPUS="${MODEL_OPUS:-claude-opus-4-6}"
MAX_LOOP_BACKS="${MAX_LOOP_BACKS:-3}"
MAX_AGENT_CALLS="${MAX_AGENT_CALLS:-50}"
BASE_URL="${BASE_URL:-http://localhost:3000}"
TEST_CMD="${TEST_CMD:-}"
SKIP_GATES="${SKIP_GATES:-}"
FEATURES_DIR="${FEATURES_DIR:-features}"
KB_DIR="${KB_DIR:-kb}"
AGENTS_DIR="${AGENTS_DIR:-.claude/agents}"
TEMPLATES_DIR="${TEMPLATES_DIR:-templates}"
PERF_P95_MS="${PERF_P95_MS:-300}"
PERF_P99_MS="${PERF_P99_MS:-1000}"
PERF_ERROR_RATE="${PERF_ERROR_RATE:-0.01}"
PERF_BUNDLE_KB="${PERF_BUNDLE_KB:-20}"

# ── Per-role max-turns ceilings ────────────────────────────────────────────────
# Override individually: make run FEATURE=foo TURNS_RED_TEAM=40
declare -A ROLE_TURNS=(
  [prd-linter]="${TURNS_PRD_LINTER:-5}"
  [architect]="${TURNS_ARCHITECT:-15}"
  [engineer]="${TURNS_ENGINEER:-20}"
  [qa]="${TURNS_QA:-20}"
  [ux]="${TURNS_UX:-10}"
  [performance]="${TURNS_PERFORMANCE:-15}"
  [cicd]="${TURNS_CICD:-6}"
  [red-team]="${TURNS_RED_TEAM:-25}"
  [push-to-pr]="${TURNS_PUSH_TO_PR:-8}"
  [steward]="${TURNS_STEWARD:-15}"
  [manager]="${TURNS_MANAGER:-4}"
)

# ── Arguments ─────────────────────────────────────────────────────────────────
INPUT="${1:-}"
RESUME="${2:-}"

if [[ -z "$INPUT" ]]; then
  echo "Usage: ./scripts/run-feature.sh features/<slug>/PRD.md"
  echo "       ./scripts/run-feature.sh features/<slug>/state.md --resume"
  echo "  Or use the Makefile: make run FEATURE=<slug>"
  exit 1
fi

FEATURE_DIR="$(cd "$(dirname "$INPUT")" && pwd)"
SLUG="$(basename "$FEATURE_DIR")"
STATE="$FEATURE_DIR/state.md"
PRD="$FEATURE_DIR/PRD.md"
CALL_COUNT_FILE="$FEATURE_DIR/.agent-calls"

echo "═══════════════════════════════════════════════"
echo "  AI Dev Factory — $SLUG"
echo "  Budget: ${MAX_AGENT_CALLS} agent calls max"
[[ -n "$SKIP_GATES" ]] && echo "  Skipping gates: $SKIP_GATES"
echo "═══════════════════════════════════════════════"

# ── Init state file for new features ──────────────────────────────────────────
if [[ ! -f "$STATE" || "$RESUME" != "--resume" ]]; then
  python3 - "$REPO_ROOT/$TEMPLATES_DIR/state-minimal.yaml" "$STATE" "$SLUG" << 'PYEOF'
import sys
src, dst, slug = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src) as f:
  content = f.read()
content = content.replace("SLUG", slug)
with open(dst, "w") as f:
  f.write(content)
PYEOF
  echo "0" > "$CALL_COUNT_FILE"
  git -C "$REPO_ROOT" checkout -b "feature/$SLUG" 2>/dev/null || \
    git -C "$REPO_ROOT" checkout "feature/$SLUG" 2>/dev/null || true
  echo "[setup] Branch: feature/$SLUG"
fi

# Ensure call counter file exists on resume
[[ -f "$CALL_COUNT_FILE" ]] || echo "0" > "$CALL_COUNT_FILE"

# ── YAML state helpers ────────────────────────────────────────────────────────

gate_status() {
  python3 - "$STATE" "$1" << 'PYEOF'
import sys, yaml
state = yaml.safe_load(open(sys.argv[1]))
keys = sys.argv[2].split(".")
v = state
for k in keys:
  v = v.get(k, {}) if isinstance(v, dict) else {}
if isinstance(v, dict):
  v = v.get("status", "pending")
print(v if v is not None else "pending")
PYEOF
}

set_state() {
  python3 - "$STATE" "$1" "$2" << 'PYEOF'
import sys, yaml
path, key_path, value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
  state = yaml.safe_load(f)
keys = key_path.split(".")
obj = state
for k in keys[:-1]:
  obj = obj.setdefault(k, {})
if value == "null":    value = None
elif value == "true":  value = True
elif value == "false": value = False
else:
  try:    value = int(value)
  except:
    try:    value = float(value)
    except: pass
obj[keys[-1]] = value
with open(path, "w") as f:
  yaml.dump(state, f, default_flow_style=None, sort_keys=False, allow_unicode=True)
PYEOF
}

check_human_pause() {
  python3 -c "
import yaml, sys
s = yaml.safe_load(open('$STATE'))
sys.exit(0 if str(s.get('status','')).strip() == 'awaiting_human' else 1)
" 2>/dev/null && {
    echo ""
    echo "⚠️  PAUSED — Human action required."
    echo "   Open: $STATE  (look for decision_requests or human_action_required)"
    echo "   After responding: make resume FEATURE=$SLUG"
    exit 0
  } || true
}

# ── Budget controls ────────────────────────────────────────────────────────────

check_budget() {
  local calls
  calls=$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo "0")
  if (( calls >= MAX_AGENT_CALLS )); then
    echo ""
    echo "⛔ Agent call budget reached ($calls / $MAX_AGENT_CALLS)."
    echo "   Increase limit: make run FEATURE=$SLUG MAX_AGENT_CALLS=$((MAX_AGENT_CALLS + 20))"
    echo "   Or edit MAX_AGENT_CALLS in .factory.env"
    set_state "status" "awaiting_human"
    set_state "human_action_required" "budget_ceiling_hit"
    exit 0
  fi
}

increment_calls() {
  local calls
  calls=$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo "0")
  echo $((calls + 1)) > "$CALL_COUNT_FILE"
}

# ── Gate skip control ─────────────────────────────────────────────────────────
# Returns 0 (run this gate) or 1 (skip it)
should_run() {
  local gate="$1"
  # Normalise: replace hyphens and underscores for comparison
  local normalised="${gate//-/_}"
  local skip="${SKIP_GATES:-}"
  # Check comma-separated skip list
  IFS=',' read -ra SKIP_LIST <<< "$skip"
  for s in "${SKIP_LIST[@]}"; do
    local s_norm="${s//-/_}"
    s_norm="${s_norm// /}"   # trim spaces
    if [[ "$normalised" == "$s_norm" ]]; then
      echo "[skip] Gate '$gate' is in SKIP_GATES — skipping."
      return 1
    fi
  done
  return 0
}

# ── Role-specific context ──────────────────────────────────────────────────────
# Each role only receives the files it actually needs.
# Red Team MUST only receive PRD — independence rule.
role_context() {
  local role="$1"
  local ctx=""
  case "$role" in
    prd-linter)
      ctx="@$PRD"
      ;;
    architect)
      ctx="@$PRD @$REPO_ROOT/$KB_DIR/INDEX.md"
      [[ -f "$STATE" ]] && ctx="$ctx @$STATE"
      ;;
    engineer)
      ctx="@$PRD"
      [[ -f "$FEATURE_DIR/adr.md" ]] && ctx="$ctx @$FEATURE_DIR/adr.md"
      [[ -f "$STATE" ]]              && ctx="$ctx @$STATE"
      ;;
    qa)
      ctx="@$PRD"
      [[ -f "$FEATURE_DIR/adr.md" ]] && ctx="$ctx @$FEATURE_DIR/adr.md"
      [[ -f "$STATE" ]]              && ctx="$ctx @$STATE"
      ;;
    ux)
      ctx="@$PRD"
      [[ -f "$STATE" ]] && ctx="$ctx @$STATE"
      ;;
    performance)
      [[ -f "$FEATURE_DIR/adr.md" ]] && ctx="@$FEATURE_DIR/adr.md"
      [[ -f "$STATE" ]]              && ctx="$ctx @$STATE"
      ;;
    cicd)
      [[ -f "$STATE" ]] && ctx="@$STATE"
      ;;
    red-team)
      ctx="@$PRD"   # PRD ONLY — no state.md, no adr.md
      ;;
    push-to-pr)
      [[ -f "$STATE" ]]              && ctx="@$STATE"
      [[ -f "$FEATURE_DIR/adr.md" ]] && ctx="$ctx @$FEATURE_DIR/adr.md"
      ;;
    steward)
      ctx="@$REPO_ROOT/$KB_DIR/INDEX.md"
      [[ -f "$STATE" ]] && ctx="$ctx @$STATE"
      ;;
    manager)
      ctx="@$STATE @$PRD"
      ;;
  esac
  echo "$ctx"
}

# ── Core agent runner ──────────────────────────────────────────────────────────
run_agent() {
  local role="$1"
  local model="$2"
  local extra_ctx="${3:-}"

  check_budget
  increment_calls

  local agent_file="$REPO_ROOT/$AGENTS_DIR/${role}.md"
  if [[ ! -f "$agent_file" ]]; then
    echo "ERROR: Agent file not found: $agent_file"
    exit 1
  fi

  local turns="${ROLE_TURNS[$role]:-15}"
  local ctx
  ctx="$(role_context "$role")"
  [[ -n "$extra_ctx" ]] && ctx="$ctx $extra_ctx"

  local calls
  calls=$(cat "$CALL_COUNT_FILE")
  echo "[${role}] call #${calls} | model=${model} | max-turns=${turns}"

  # Inject runtime config into the prompt so agents don't hardcode paths/values
  local config_ctx
  config_ctx="$(cat << CONF
Runtime config:
  feature_slug: $SLUG
  feature_dir:  $FEATURE_DIR
  base_url:     $BASE_URL
  test_cmd:     ${TEST_CMD:-auto-detect}
  perf_budgets: p95=${PERF_P95_MS}ms p99=${PERF_P99_MS}ms error_rate=${PERF_ERROR_RATE} bundle=${PERF_BUNDLE_KB}KB
CONF
)"

  local prompt
  prompt="$(cat "$agent_file")

---
$config_ctx
$(for f in $ctx; do echo "Context: $f"; done)"

  claude -p "$prompt" \
    --model "$model" \
    --max-turns "$turns" \
    2>&1

  echo "[${role}] ✓"
}

# =============================================================================
# MAIN LOOP
# =============================================================================
echo ""

# ── 0. PRD Lint ────────────────────────────────────────────────────────────────
if should_run "prd_linter" && [[ "$(gate_status 'prd_linter.status')" != "pass" ]]; then
  run_agent "prd-linter" "$MODEL_HAIKU"
  check_human_pause
fi

# ── 1. Architect ───────────────────────────────────────────────────────────────
if should_run "architect" && [[ "$(gate_status 'architect.status')" != "complete" ]]; then
  run_agent "architect" "$MODEL_OPUS"
  check_human_pause
fi

# ── 2. Engineer ────────────────────────────────────────────────────────────────
ENGINEER_LOOPS=0
while should_run "engineer" && [[ "$(gate_status 'engineer.status')" != "complete" ]]; do
  if (( ENGINEER_LOOPS >= MAX_LOOP_BACKS )); then
    echo "[engineer] Loop-back ceiling ($MAX_LOOP_BACKS) reached."
    set_state "status" "awaiting_human"; check_human_pause
  fi
  run_agent "engineer" "$MODEL_SONNET"
  check_human_pause
  ENGINEER_LOOPS=$(( ENGINEER_LOOPS + 1 ))
done

# ── 3. QA ──────────────────────────────────────────────────────────────────────
QA_LOOPS=0
while should_run "qa" && [[ "$(gate_status 'qa.status')" != "complete" ]]; do
  if (( QA_LOOPS >= MAX_LOOP_BACKS )); then
    set_state "status" "awaiting_human"; check_human_pause
  fi
  run_agent "qa" "$MODEL_SONNET"
  check_human_pause
  QA_LOOPS=$(( QA_LOOPS + 1 ))
done

# ── 4. UX ──────────────────────────────────────────────────────────────────────
UX_LOOPS=0
UX_MODEL="$MODEL_HAIKU"
while should_run "ux" && [[ "$(gate_status 'ux.status')" != "complete" ]]; do
  if (( UX_LOOPS >= MAX_LOOP_BACKS )); then
    set_state "status" "awaiting_human"; check_human_pause
  fi
  [[ $UX_LOOPS -ge 1 ]] && UX_MODEL="$MODEL_SONNET"
  run_agent "ux" "$UX_MODEL"
  UX_P0="$(gate_status 'ux.p0_count')"
  UX_P1="$(gate_status 'ux.p1_count')"
  if [[ "$UX_P0" != "0" && "$UX_P0" != "null" ]] || \
     [[ "$UX_P1" != "0" && "$UX_P1" != "null" ]]; then
    echo "[ux] P0/P1 findings — looping back to engineer..."
    set_state "engineer.status" "pending"
    set_state "qa.status" "pending"
    set_state "ux.status" "pending"
    run_agent "engineer" "$MODEL_SONNET" "@$FEATURE_DIR/ux-review.md"
    check_human_pause
    run_agent "qa" "$MODEL_SONNET"
    check_human_pause
  fi
  check_human_pause
  UX_LOOPS=$(( UX_LOOPS + 1 ))
done

# ── 5. Performance ─────────────────────────────────────────────────────────────
PERF_LOOPS=0
while should_run "performance" && [[ "$(gate_status 'performance.status')" != "complete" ]]; do
  if (( PERF_LOOPS >= MAX_LOOP_BACKS )); then
    set_state "status" "awaiting_human"; check_human_pause
  fi
  run_agent "performance" "$MODEL_SONNET"
  check_human_pause
  PERF_LOOPS=$(( PERF_LOOPS + 1 ))
done

# ── 6. CI/CD ───────────────────────────────────────────────────────────────────
if should_run "cicd" && [[ "$(gate_status 'cicd.status')" != "complete" ]]; then
  run_agent "cicd" "$MODEL_HAIKU"
  check_human_pause
fi

# ── 7. Red Team ────────────────────────────────────────────────────────────────
RED_LOOPS=0
while should_run "red_team" && [[ "$(gate_status 'red_team.status')" != "complete" ]]; do
  if (( RED_LOOPS >= MAX_LOOP_BACKS )); then
    set_state "status" "awaiting_human"; check_human_pause
  fi
  run_agent "red-team" "$MODEL_SONNET"
  RED_P0="$(gate_status 'red_team.p0_count')"
  if [[ "$RED_P0" != "0" && "$RED_P0" != "null" ]]; then
    echo "⚠️  Red Team P0 finding — human sign-off required."
    set_state "status" "awaiting_human"; check_human_pause
  fi
  RED_LOOPS=$(( RED_LOOPS + 1 ))
done

# ── 8. Push to PR ──────────────────────────────────────────────────────────────
if [[ "$(gate_status 'push_to_pr.status')" != "complete" ]]; then
  run_agent "push-to-pr" "$MODEL_HAIKU"
  check_human_pause
fi

TOTAL_CALLS=$(cat "$CALL_COUNT_FILE")
echo ""
echo "═══════════════════════════════════════════════"
echo "  ✅ All gates passed. PR is open."
echo "  PR:   $(gate_status 'push_to_pr.pr_url')"
echo "  Used: $TOTAL_CALLS / $MAX_AGENT_CALLS agent calls"
echo ""
echo "  Next:  Review → approve → merge, then:"
echo "         make steward FEATURE=$SLUG"
echo "═══════════════════════════════════════════════"
