# Onboarding — How to Use the AI Dev Factory

## Prerequisites

```bash
# 1. Claude CLI installed and authenticated with Max plan
claude --version
claude login  # authenticate with your Max subscription

# 2. CRITICAL: unset API key so billing goes through Max, not API
unset ANTHROPIC_API_KEY
echo "Verify: ANTHROPIC_API_KEY should be empty below"
echo "${ANTHROPIC_API_KEY:-empty ✅}"

# 3. GitHub CLI (for PR creation)
gh --version
gh auth login

# 4. k6 (for performance tests)
k6 version

# 5. Install git hooks (run once)
./scripts/setup-hooks.sh
```

---

## Starting a Feature

### Step 1 — Write the PRD

```bash
# Create the feature folder
SLUG="user-login"   # kebab-case, no spaces
mkdir -p features/$SLUG

# Copy and fill in the PRD template
cp templates/PRD.md features/$SLUG/PRD.md
# Edit features/$SLUG/PRD.md — fill every section
```

The PRD is the only thing you write. It is the contract. Vague PRDs fail the linter and come back to you immediately — it's faster to be specific upfront.

### Step 2 — Start the loop

```bash
./scripts/run-feature.sh features/$SLUG/PRD.md
```

The loop runs: PRD Lint → Architect → Engineer → QA → UX → Performance → CI/CD → Red Team → Push-to-PR.

### Step 3 — Respond to pauses

The loop pauses and notifies you (via `state.md` + GitHub) when:
- The PRD linter found something ambiguous — fix the PRD, re-run
- An agent has low confidence and needs a decision — answer in `state.md`, re-run with `--resume`
- A gate failed 3 times — something structural needs your input
- Red Team found a P0 security issue — your call

```bash
# Resume after responding to a pause
./scripts/run-feature.sh features/$SLUG/state.md --resume
```

### Step 4 — Review the PR

When the loop finishes, a PR is open. The PR description includes:
- The ADR (why this approach)
- Test results and mutation score
- Performance numbers vs. budgets
- Red Team summary and regression tests added
- Assumption log

Review it as you would any PR. Approve and merge.

### Step 5 — Post-merge Steward pass

```bash
./scripts/run-steward.sh $SLUG
```

This ingests any learnings from the feature into the KB. Takes 2–5 minutes.

---

## Running from the Cloud (overnight / remote)

Use Claude Code on the web (claude.ai/code):
1. Connect your GitHub repo
2. In the prompt: `"Run ./scripts/run-feature.sh features/<slug>/PRD.md and follow the loop through to a PR. Use the state.md case file for all loop state."`
3. The session runs in Anthropic's cloud VM — persists while you sleep
4. Check GitHub mobile for PR notification in the morning

---

## Resuming an Interrupted Feature

If a session ends mid-loop (usage limit, network drop, etc.):

```bash
./scripts/run-feature.sh features/$SLUG/state.md --resume
```

The script reads `state.md`, sees which gates are already `complete`, and picks up from the last incomplete gate. Nothing is lost.

---

## Scheduled Steward Pass (weekly hygiene)

```bash
./scripts/run-steward.sh --full-pass
```

Runs KB dedup, docs correctness check, and agent file audit. Schedule it weekly (cron or a reminder to yourself).

---

## Key Files to Know

| File | Owner | Purpose |
|------|-------|---------|
| `features/<slug>/PRD.md` | You | Feature intent — agents never modify this |
| `features/<slug>/state.md` | Loop | Case file — all loop state, gate statuses, decisions |
| `CLAUDE.md` | You + Steward (proposals) | Always-loaded standards |
| `kb/INDEX.md` | Steward | Knowledge base index |
| `claude-agents/*.md` | You + Steward (proposals) | Agent role definitions |

---

## Troubleshooting

**"ANTHROPIC_API_KEY is set" error**
```bash
unset ANTHROPIC_API_KEY
```

**Loop stuck on a gate repeatedly**
Check `state.md` → `loop_back_counts` and `decision_requests`. The loop is probably waiting for human input.

**k6 not installed**
```bash
# macOS
brew install k6
# Linux
sudo apt install k6
```

**gh CLI not authenticated**
```bash
gh auth login
```
