#!/usr/bin/env bash
# =============================================================================
# install.sh — Set up the AI Dev Factory in any git repository.
#
# RECOMMENDED (submodule — zero repo pollution):
#   git submodule add https://github.com/you/ai-dev-factory tools/ai-dev-factory
#   bash tools/ai-dev-factory/install.sh
#
# ALTERNATIVE (copy into repo):
#   cp -r ai-dev-factory/ your-repo/tools/ai-dev-factory/
#   bash your-repo/tools/ai-dev-factory/install.sh
#
# What this does:
#   1. Checks prerequisites (claude, gh, k6, python3, pyyaml)
#   2. Installs agent files → repo-root/.claude/agents/
#   3. Installs/merges CLAUDE.md at repo root
#   4. Submodule mode: stops here (scripts/kb/templates stay inside factory dir)
#      Standalone mode: also copies scripts/, kb/, templates/, docs/ to repo root
#   5. Installs git hooks
#   6. Runs a self-test
#   7. Prints the three lines to add to your Makefile
# =============================================================================

set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✅ $*${NC}"; }
warn() { echo -e "${YELLOW}  ⚠️  $*${NC}"; }
fail() { echo -e "${RED}  ❌ $*${NC}"; ERRORS=$((ERRORS+1)); }
ERRORS=0

# ── Locate factory dir and repo root ─────────────────────────────────────────
FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect if we're inside a git submodule
SUPERPROJECT="$(git -C "$FACTORY_DIR" rev-parse --show-superproject-working-tree 2>/dev/null || true)"

if [[ -n "$SUPERPROJECT" ]]; then
  # Running as a submodule — repo root is the superproject
  REPO_ROOT="$(cd "$SUPERPROJECT" && pwd)"
  SUBMODULE_MODE=true
else
  # Standalone — try git to find repo root, fall back to parent dir
  REPO_ROOT="$(git -C "$FACTORY_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$REPO_ROOT" ]]; then
    REPO_ROOT="$(cd "$FACTORY_DIR/.." && pwd)"
  fi
  REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
  SUBMODULE_MODE=false
fi

# Relative path from repo root to factory dir (used in printed snippets)
FACTORY_REL="${FACTORY_DIR#$REPO_ROOT/}"

echo ""
echo "═══════════════════════════════════════════════"
echo "  AI Dev Factory — Install"
if [[ "$SUBMODULE_MODE" == "true" ]]; then
  echo "  Mode:    submodule (clean — factory stays in ${FACTORY_REL}/)"
else
  echo "  Mode:    standalone"
fi
echo "  Factory: $FACTORY_DIR"
echo "  Repo:    $REPO_ROOT"
echo "═══════════════════════════════════════════════"
echo ""

# ─── Step 1: Prerequisites ────────────────────────────────────────────────────
echo "[ 1/6 ] Checking prerequisites..."

if command -v claude &>/dev/null; then
  ok "claude CLI found: $(claude --version 2>/dev/null | head -1)"
else
  fail "claude CLI not found. Install: https://docs.anthropic.com/claude-code"
fi

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  warn "ANTHROPIC_API_KEY is set — this bills the API, not your Max plan."
  warn "  Run:  unset ANTHROPIC_API_KEY   then:  claude login"
else
  ok "ANTHROPIC_API_KEY is unset (will use Max plan ✓)"
fi

if command -v gh &>/dev/null; then
  ok "gh CLI found: $(gh --version | head -1)"
else
  fail "gh CLI not found. Install: https://cli.github.com  then: gh auth login"
fi

if command -v k6 &>/dev/null; then
  ok "k6 found: $(k6 version 2>/dev/null | head -1)"
else
  warn "k6 not found — performance gate will fail until installed."
  warn "  macOS:  brew install k6"
  warn "  Linux:  https://k6.io/docs/getting-started/installation/"
fi

if command -v python3 &>/dev/null; then
  ok "python3 found: $(python3 --version)"
  if python3 -c "import yaml" 2>/dev/null; then
    ok "pyyaml found"
  else
    echo "  Installing pyyaml..."
    python3 -m pip install pyyaml --quiet --break-system-packages 2>/dev/null || \
    python3 -m pip install pyyaml --quiet 2>/dev/null || \
    pip3 install pyyaml --quiet 2>/dev/null || true
    if python3 -c "import yaml" 2>/dev/null; then
      ok "pyyaml installed"
    else
      fail "pyyaml could not be installed. Run: pip3 install pyyaml"
    fi
  fi
else
  fail "python3 not found — required for YAML state management."
fi

echo ""

# ─── Step 2: Agent files → .claude/agents/ ───────────────────────────────────
echo "[ 2/6 ] Setting up .claude/agents/..."

AGENTS_SRC="$FACTORY_DIR/claude-agents"
AGENTS_DST="$REPO_ROOT/.claude/agents"

if [[ -d "$AGENTS_SRC" ]]; then
  mkdir -p "$REPO_ROOT/.claude"
  if [[ -d "$AGENTS_DST" ]]; then
    for f in "$AGENTS_SRC"/*.md; do
      name="$(basename "$f")"
      if [[ -f "$AGENTS_DST/$name" ]]; then
        warn "$name already exists — keeping existing. New version saved as: .claude/agents/${name%.md}.factory.md"
        cp "$f" "$AGENTS_DST/${name%.md}.factory.md"
      else
        cp "$f" "$AGENTS_DST/$name"
        ok "Installed agent: $name"
      fi
    done
  else
    cp -r "$AGENTS_SRC" "$AGENTS_DST"
    ok "Installed .claude/agents/ ($(ls "$AGENTS_DST"/*.md | wc -l | tr -d ' ') agent files)"
  fi
else
  if [[ -d "$AGENTS_DST" ]]; then
    ok ".claude/agents/ already exists"
  else
    fail "claude-agents/ not found at $AGENTS_SRC and .claude/agents/ not found either."
  fi
fi

echo ""

# ─── Step 3: CLAUDE.md ────────────────────────────────────────────────────────
echo "[ 3/6 ] Setting up CLAUDE.md..."

CLAUDE_SRC="$FACTORY_DIR/CLAUDE.md"
CLAUDE_DST="$REPO_ROOT/CLAUDE.md"

if [[ -f "$CLAUDE_DST" ]]; then
  warn "CLAUDE.md already exists — factory version saved as CLAUDE.factory.md."
  warn "  Merge manually: append the factory sections to your existing CLAUDE.md."
  cp "$CLAUDE_SRC" "$REPO_ROOT/CLAUDE.factory.md"
else
  cp "$CLAUDE_SRC" "$CLAUDE_DST"
  ok "Installed CLAUDE.md"
fi

echo ""

# ─── Step 4: Support files ────────────────────────────────────────────────────
if [[ "$SUBMODULE_MODE" == "true" ]]; then
  echo "[ 4/6 ] Submodule mode — engine files stay inside ${FACTORY_REL}/"
  echo "        Creating project-owned directories at repo root..."

  # features/ at repo root — PRDs and state are project artifacts
  mkdir -p "$REPO_ROOT/features"
  touch "$REPO_ROOT/features/.gitkeep"
  ok "features/ ready at repo root"

  # kb/ at repo root — PROJECT knowledge base (committed to your repo, not the engine)
  if [[ ! -d "$REPO_ROOT/kb" ]]; then
    mkdir -p "$REPO_ROOT/kb"
    cat > "$REPO_ROOT/kb/INDEX.md" << 'KBEOF'
# Knowledge Base — Project Index

This is your **project-specific** knowledge base, committed to this repository
and shared with your whole team.

AutoCodeEngine's Steward writes project-specific learnings here after each feature
merges. Learnings that apply to any codebase are proposed as PRs to the
AutoCodeEngine engine KB instead.

## How to use

Agents read this index first, then load at most 2 files from the entries below.
Never scan the kb/ directory directly — always go through this index.

## Entries

<!-- Steward will populate this as learnings are added. -->
<!-- Format: - [domain/file.md](domain/file.md) — one-line description -->
KBEOF
    ok "kb/ created at repo root with starter INDEX.md"
  else
    ok "kb/ already exists at repo root — skipping"
  fi

  # Ensure engine scripts are executable
  find "$FACTORY_DIR/scripts" -name "*.sh" -exec chmod +x {} \;
  ok "chmod +x on engine scripts"
else
  echo "[ 4/6 ] Standalone mode — copying support files to repo root..."

  for dir in kb templates docs; do
    if [[ ! -d "$REPO_ROOT/$dir" ]]; then
      cp -r "$FACTORY_DIR/$dir" "$REPO_ROOT/$dir"
      ok "Installed $dir/"
    else
      warn "$dir/ already exists — skipping. Copy missing files from $FACTORY_DIR/$dir/ manually."
    fi
  done

  mkdir -p "$REPO_ROOT/features"
  touch "$REPO_ROOT/features/.gitkeep"
  ok "features/ ready"

  if [[ ! -d "$REPO_ROOT/scripts" ]]; then
    cp -r "$FACTORY_DIR/scripts" "$REPO_ROOT/scripts"
    ok "Installed scripts/"
  else
    warn "scripts/ already exists — copying factory scripts with .factory suffix."
    for f in "$FACTORY_DIR/scripts"/*.sh; do
      name="$(basename "$f")"
      if [[ ! -f "$REPO_ROOT/scripts/$name" ]]; then
        cp "$f" "$REPO_ROOT/scripts/$name"
        ok "  Installed scripts/$name"
      else
        warn "  scripts/$name exists — saved as scripts/${name%.sh}.factory.sh"
        cp "$f" "$REPO_ROOT/scripts/${name%.sh}.factory.sh"
      fi
    done
    mkdir -p "$REPO_ROOT/scripts/hooks"
    for f in "$FACTORY_DIR/scripts/hooks"/*.sh; do
      cp "$f" "$REPO_ROOT/scripts/hooks/$(basename "$f")"
    done
    ok "Installed scripts/hooks/"
  fi

  find "$REPO_ROOT/scripts" -name "*.sh" -exec chmod +x {} \;
  ok "chmod +x on all scripts"
fi

echo ""

# ─── Step 5: Git hooks ────────────────────────────────────────────────────────
echo "[ 5/6 ] Installing git hooks..."

HOOKS_SCRIPT="$FACTORY_DIR/scripts/setup-hooks.sh"

if [[ -d "$REPO_ROOT/.git" ]] && [[ -f "$HOOKS_SCRIPT" ]]; then
  bash "$HOOKS_SCRIPT"
  ok "Git hooks installed (pre-commit, pre-push)"
elif [[ ! -d "$REPO_ROOT/.git" ]]; then
  warn "No .git directory — hooks skipped. Run: git init && bash ${FACTORY_REL}/scripts/setup-hooks.sh"
else
  warn "setup-hooks.sh not found at $HOOKS_SCRIPT — hooks skipped."
fi

echo ""

# ─── Step 6: Self-test ────────────────────────────────────────────────────────
echo "[ 6/6 ] Running self-test..."

TEST_STATE="/tmp/factory-test-state.yaml"
cat > "$TEST_STATE" << 'YAML'
feature_slug: test
status: in_progress
architect: {status: complete, confidence: 0.9}
engineer: {status: pending, confidence: null}
loop_backs: {architect: 0, engineer: 1}
YAML

ARCH_STATUS=$(python3 - "$TEST_STATE" "architect.status" << 'PYEOF'
import sys, yaml
state = yaml.safe_load(open(sys.argv[1]))
keys = sys.argv[2].split(".")
v = state
for k in keys:
  v = v.get(k, {}) if isinstance(v, dict) else {}
if isinstance(v, dict): v = v.get("status", "pending")
print(v if v is not None else "pending")
PYEOF
)

if [[ "$ARCH_STATUS" == "complete" ]]; then
  ok "YAML parser works (architect.status = $ARCH_STATUS)"
else
  fail "YAML parser returned '$ARCH_STATUS', expected 'complete'"
fi

TEMPLATE_FILE="$FACTORY_DIR/templates/state-minimal.yaml"
if [[ -f "$TEMPLATE_FILE" ]]; then
  ok "state-minimal.yaml template present"
else
  fail "templates/state-minimal.yaml not found at $TEMPLATE_FILE"
fi

AGENT_COUNT=$(ls "$REPO_ROOT/.claude/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
if [[ "$AGENT_COUNT" -ge 10 ]]; then
  ok "$AGENT_COUNT agent files in .claude/agents/"
else
  fail "Only $AGENT_COUNT agent files found in .claude/agents/ — expected ≥10"
fi

rm -f "$TEST_STATE"

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}✅ Install complete.${NC}"
  echo ""

  if [[ "$SUBMODULE_MODE" == "true" ]]; then
    echo "  Add these lines to your repo's Makefile (or create one):"
    echo ""
    echo -e "  ${CYAN}  # ── AI Dev Factory ──────────────────────────────"
    echo "  include ${FACTORY_REL}/factory.mk"
    echo -e "  # ─────────────────────────────────────────────────${NC}"
    echo ""
    echo "  Copy and edit the config:"
    echo "    cp ${FACTORY_REL}/.factory.env.example .factory.env"
    echo ""
  else
    echo "  Add to your Makefile (or rename factory.mk to Makefile):"
    echo ""
    echo -e "  ${CYAN}  include ${FACTORY_REL}/factory.mk${NC}"
    echo ""
    echo "  Copy and edit the config:"
    echo "    cp ${FACTORY_REL}/.factory.env.example .factory.env"
    echo ""
  fi

  echo "  Then start your first feature:"
  echo "    make new FEATURE=my-first-feature"
  echo "    # Edit the PRD, then:"
  echo "    make run FEATURE=my-first-feature"
  echo ""
  echo "  Run  make help  to see all available commands."
else
  echo -e "  ${RED}⚠️  Install completed with $ERRORS error(s) above.${NC}"
  echo "  Fix the errors above, then re-run this script."
fi
echo "═══════════════════════════════════════════════"
echo ""
