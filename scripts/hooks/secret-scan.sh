#!/usr/bin/env bash
# secret-scan.sh — Scan staged files for secrets before commit.
# Called by the pre-commit hook. Exit 0 = clean. Exit 1 = secrets found.

set -euo pipefail

echo "[secret-scan] Scanning staged files..."

# Patterns that indicate a secret — extend this list for your stack
SECRET_PATTERNS=(
  "AKIA[0-9A-Z]{16}"                           # AWS Access Key
  "-----BEGIN (RSA|EC|OPENSSH) PRIVATE KEY"    # Private keys
  "sk-[a-zA-Z0-9]{32,}"                        # OpenAI / Anthropic API keys
  "ghp_[a-zA-Z0-9]{36}"                        # GitHub personal access token
  "password\s*=\s*['\"][^'\"]{6,}"             # Hardcoded password
  "secret\s*=\s*['\"][^'\"]{6,}"               # Hardcoded secret
  "api[_-]?key\s*[=:]\s*['\"][^'\"]{8,}"       # Generic API key
  "token\s*[=:]\s*['\"][^'\"]{8,}"             # Generic token
)

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)

if [[ -z "$STAGED_FILES" ]]; then
  echo "[secret-scan] No staged files."
  exit 0
fi

FOUND=0

for pattern in "${SECRET_PATTERNS[@]}"; do
  MATCHES=$(echo "$STAGED_FILES" | xargs grep -lE "$pattern" 2>/dev/null || true)
  if [[ -n "$MATCHES" ]]; then
    echo "❌ POTENTIAL SECRET FOUND matching pattern: $pattern"
    echo "   In files: $MATCHES"
    FOUND=1
  fi
done

# Also check with git-secrets if installed
if command -v git-secrets &>/dev/null; then
  git secrets --scan-staged 2>&1 || FOUND=1
fi

if [[ $FOUND -eq 1 ]]; then
  echo ""
  echo "Secret scan FAILED. Remove secrets before committing."
  echo "If this is a false positive, add an exception to .gitallowed"
  exit 1
fi

echo "[secret-scan] ✅ Clean."
exit 0
