#!/usr/bin/env bash
# setup-hooks.sh — Install git hooks for this repo.
# Run once after cloning: ./scripts/setup-hooks.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo "[setup-hooks] Installing git hooks..."

# ── pre-commit: lint + type-check + secret scan ──────────────────────────────
cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"

echo "[pre-commit] Running lint..."

# Secret scan (always)
"$REPO_ROOT/scripts/hooks/secret-scan.sh"

# Adapt to your stack:
# Node: npx eslint --ext .js,.ts src/ && npx tsc --noEmit
# Python: ruff check . && mypy .
# Go: go vet ./...

echo "[pre-commit] ✅ Pre-commit checks passed."
EOF
chmod +x "$HOOKS_DIR/pre-commit"

# ── pre-push: full test suite ─────────────────────────────────────────────────
cat > "$HOOKS_DIR/pre-push" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"

echo "[pre-push] Running full test suite — this blocks push on red..."
"$REPO_ROOT/scripts/hooks/run-tests.sh"
echo "[pre-push] ✅ Tests passed. Proceeding with push."
EOF
chmod +x "$HOOKS_DIR/pre-push"

# ── Make all hook scripts executable ─────────────────────────────────────────
chmod +x "$REPO_ROOT/scripts/hooks/"*.sh
chmod +x "$REPO_ROOT/scripts/"*.sh

echo "[setup-hooks] ✅ Done."
echo ""
echo "Installed hooks:"
echo "  pre-commit  → lint + secret scan"
echo "  pre-push    → full test suite"
