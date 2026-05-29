# AutoCodeEngine

An AI-driven software development framework that turns a Product Requirements Document into production-ready code using a team of specialized AI agents — fully automated, self-improving, and designed to run in any git repository without polluting it.

Built on [Claude Code](https://docs.anthropic.com/claude-code) and the Claude Max plan (no API billing).

---

## How It Works

You write a PRD. AutoCodeEngine runs it through a sequential quality gate pipeline, each gate staffed by a specialized agent. Agents write code, tests, and docs; the loop detects failures and retries; humans only intervene at real decision points.

```
PRD.md
  │
  ▼
┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│  PRD Linter │ → │  Architect  │ → │  Engineer   │ → │     QA      │
│  (haiku)    │   │  (opus)     │   │  (sonnet)   │   │  (sonnet)   │
└─────────────┘   └─────────────┘   └─────────────┘   └─────────────┘
                                                               │
┌─────────────┐   ┌─────────────┐   ┌─────────────┐          │
│  Push-to-PR │ ← │   CI/CD     │ ← │  Red Team   │          │
│  (haiku)    │   │  (haiku)    │   │  (sonnet)   │          │
└─────────────┘   └─────────────┘   └─────────────┘          │
                                                               ▼
                        ┌─────────────┐   ┌─────────────────────────┐
                        │  Performance│ ← │          UX             │
                        │  (sonnet)   │   │        (haiku)          │
                        └─────────────┘   └─────────────────────────┘
```

State is tracked in a YAML file (`features/<slug>/state.yaml`). Every agent reads it, does its work, and writes its result back. The loop advances, retries on failure, and pauses for human review only when it truly can't proceed.

---

## Key Principles

- **One branch per feature** — no parallel work, no merge conflicts from agents
- **Test-first** — Engineer writes tests before code; QA runs mutation testing (≥70% threshold)
- **Red Team independence** — receives only the PRD, never the implementation; prevents whitebox bias
- **KB self-improvement** — every run produces generalizable learnings that flow into `kb/`; future runs benefit from past runs
- **Budget ceiling** — configurable max agent calls per feature (default 50); loop pauses and hands off to human when hit
- **Max plan only** — never set `ANTHROPIC_API_KEY`; uses Claude Max plan, not API billing
- **Stateless agents** — all state lives in files and git; agents are pure functions over the file system

---

## Agents

| Agent | Model | Role | Max Turns |
|-------|-------|------|-----------|
| **PRD Linter** | Haiku | Validates PRD completeness and clarity before any code work | 5 |
| **Architect** | Opus | Produces ADR (Architecture Decision Record): tech stack, data models, API contracts, security model | 15 |
| **Engineer** | Sonnet | Writes tests first, then implements to make them pass; follows SOLID principles | 20 |
| **QA** | Sonnet | Runs full test suite, mutation testing (≥70%), integration tests; approves or rejects | 20 |
| **UX** | Haiku | Reviews UI/API ergonomics, accessibility, error messages, empty states | 10 |
| **Performance** | Sonnet | Runs k6 load tests against `BASE_URL`; enforces p95/p99/error-rate/bundle-size budgets | 15 |
| **CI/CD** | Haiku | Sets up or validates CI pipeline, lint, type-check, test commands | 6 |
| **Red Team** | Sonnet | Security review — receives PRD only (no implementation context); finds auth, injection, data exposure issues | 25 |
| **Push-to-PR** | Haiku | Creates git branch, commits, pushes, opens GitHub PR with summary | 8 |
| **Steward** | Haiku | Post-merge KB ingestion and weekly hygiene pass; keeps `kb/` accurate and deduplicated | 15 |

### Model selection rationale

- **Haiku** — fast and cheap for mechanical tasks (linting, CI setup, PR creation, maintenance)
- **Sonnet** — main workhorse for code, tests, security, performance analysis
- **Opus** — used only once per feature (Architect) where deep reasoning justifies the cost

---

## File Structure

```
AutoCodeEngine/                   ← the engine (lives as a submodule in target repos)
│
├── install.sh                    ← one-time setup for any repo
├── factory.mk                    ← Makefile interface (include this in your Makefile)
├── .factory.env.example          ← copy to .factory.env at repo root and edit
│
├── claude-agents/                ← agent definitions (installed to .claude/agents/ by install.sh)
│   ├── architect.md
│   ├── engineer.md
│   ├── qa.md
│   ├── ux.md
│   ├── performance.md
│   ├── cicd.md
│   ├── red-team.md
│   ├── push-to-pr.md
│   ├── prd-linter.md
│   ├── steward.md
│   └── manager.md
│
├── scripts/
│   ├── run-feature.sh            ← main orchestration loop
│   ├── run-steward.sh            ← post-merge KB ingestion
│   ├── show-status.sh            ← gate dashboard (make status / make list)
│   ├── show-budget.sh            ← agent call budget meter (make budget)
│   ├── setup-hooks.sh            ← installs git pre-commit / pre-push hooks
│   └── hooks/
│       ├── run-tests.sh          ← pre-push: run full test suite
│       ├── run-k6.sh             ← performance regression check
│       └── secret-scan.sh        ← blocks commits with secrets/API keys
│
├── templates/
│   ├── PRD.md                    ← feature PRD template (make new copies this)
│   ├── state-minimal.yaml        ← fresh state file (created per feature on run)
│   └── state.md                  ← annotated state template (reference)
│
├── kb/                           ← self-improving knowledge base
│   ├── INDEX.md                  ← agents read this first; never scan kb/ directly
│   ├── architecture/
│   ├── engineering/
│   ├── testing/
│   ├── performance/
│   ├── security/
│   ├── cicd/
│   ├── ux/
│   └── archive/                  ← archived entries (never hard-deleted)
│
├── docs/
│   ├── architecture.md           ← system design and agent interaction diagrams
│   └── onboarding.md             ← new team member guide
│
└── features/                     ← one folder per feature
    └── <slug>/
        ├── PRD.md                ← you write this
        ├── state.yaml            ← loop writes and reads this
        └── .agent-calls          ← call counter (gitignored)
```

When installed as a submodule, only two things go to your repo root:
- `.claude/agents/` — Claude Code requires agents here
- `CLAUDE.md` — always-loaded project context

Everything else stays inside the submodule.

---

## Setup

### Option A — Git submodule (recommended)

Zero repo pollution. The engine lives in `tools/autocode/`; nothing else touches your repo.

```bash
# 1. Add as submodule
git submodule add https://github.com/you/AutoCodeEngine tools/autocode

# 2. Run installer (detects submodule mode automatically)
bash tools/autocode/install.sh

# 3. Copy and edit config
cp tools/autocode/.factory.env.example .factory.env
# Edit .factory.env — set TEST_CMD, BASE_URL, SKIP_GATES as needed

# 4. Add to your Makefile (or create one)
echo 'include tools/autocode/factory.mk' >> Makefile
```

After `git clone` on another machine:
```bash
git submodule update --init
bash tools/autocode/install.sh
```

### Option B — Direct copy (standalone)

```bash
cp -r AutoCodeEngine/ your-repo/tools/autocode/
bash your-repo/tools/autocode/install.sh
echo 'include tools/autocode/factory.mk' >> your-repo/Makefile
```

### Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| `claude` CLI | Runs agents | [docs.anthropic.com/claude-code](https://docs.anthropic.com/claude-code) |
| `gh` CLI | Opens GitHub PRs | `brew install gh` then `gh auth login` |
| `k6` | Performance load tests | `brew install k6` |
| `python3` + `pyyaml` | YAML state management | `pip3 install pyyaml` |

> **Important:** Do not set `ANTHROPIC_API_KEY`. If it's set, usage bills to the API rather than your Max plan. Run `unset ANTHROPIC_API_KEY` and re-authenticate with `claude login`.

---

## Usage

All commands go through `make`. Run `make help` at any time to see the full list with current config values.

### Start a new feature

```bash
# Create a PRD from template
make new FEATURE=user-authentication

# Edit the PRD — fill in every section
$EDITOR features/user-authentication/PRD.md

# Run the full pipeline
make run FEATURE=user-authentication
```

### Monitor progress

```bash
# Gate-by-gate dashboard for a feature
make status FEATURE=user-authentication

# List all features and their status
make list

# Agent call budget meter
make budget FEATURE=user-authentication
```

### Resume after interruption

```bash
# Resume a paused or interrupted run
make resume FEATURE=user-authentication
```

### Post-merge knowledge base update

```bash
# After merging the PR — ingest learnings into kb/
make steward FEATURE=user-authentication

# Weekly deep hygiene pass (dedup, stale entry cleanup, diagram audit)
make steward-deep
```

### Housekeeping

```bash
# Reset state for a feature (keeps PRD and code, wipes state.yaml + call counter)
make clean FEATURE=user-authentication

# Verify prerequisites without running install
make check
```

---

## Configuration

All config lives in `.factory.env` at your repo root (gitignored, never committed). Copy `.factory.env.example` to get started.

### Models

```bash
MODEL_HAIKU=claude-haiku-4-5       # fast/cheap — linter, ci/cd, ux, steward, push-to-pr
MODEL_SONNET=claude-sonnet-4-5     # main work — engineer, qa, performance, red-team
MODEL_OPUS=claude-opus-4-6         # best reasoning — architect only (once per feature)
```

### Loop controls

```bash
MAX_LOOP_BACKS=3     # max retries per gate before pausing for human input
MAX_AGENT_CALLS=50   # hard ceiling on total agent calls per feature run
                     # a clean run uses ~11–15 calls; 50 allows generous loop-backs
```

### Project settings

```bash
BASE_URL=http://localhost:3000    # k6 load tests hit this URL
TEST_CMD=                         # leave empty for auto-detection (jest/pytest/go test/rspec)
                                  # or set explicitly: TEST_CMD=npm test
```

### Skip gates

For projects where certain gates don't apply:

```bash
SKIP_GATES=ux,performance          # backend-only repo — skip UI/perf gates
SKIP_GATES=performance             # if k6 isn't set up yet
SKIP_GATES=                        # empty = run all gates (default, recommended)
```

Available gate names: `prd_linter`, `architect`, `engineer`, `qa`, `ux`, `performance`, `cicd`, `red_team`, `push_to_pr`

### Performance budgets

```bash
PERF_P95_MS=300       # p95 latency budget in milliseconds
PERF_P99_MS=1000      # p99 latency budget in milliseconds
PERF_ERROR_RATE=0.01  # max error rate (1%)
PERF_BUNDLE_KB=20     # max JS bundle size in KB
```

### Per-agent turn limits

Override any agent's max turns without changing the scripts:

```bash
TURNS_ARCHITECT=15
TURNS_ENGINEER=20
TURNS_QA=20
TURNS_RED_TEAM=25
TURNS_UX=10
TURNS_PERFORMANCE=15
TURNS_CICD=6
TURNS_PRD_LINTER=5
TURNS_PUSH_TO_PR=8
TURNS_STEWARD=15
```

### Runtime overrides

Any config variable can be overridden on the command line for a single run:

```bash
make run FEATURE=auth MAX_AGENT_CALLS=30
make run FEATURE=auth MODEL_SONNET=claude-sonnet-4-5 SKIP_GATES=ux
make budget FEATURE=auth MAX_AGENT_CALLS=75
```

---

## The Feature Loop in Detail

When you run `make run FEATURE=<slug>`, `scripts/run-feature.sh`:

1. **Initialises state** — copies `templates/state-minimal.yaml` to `features/<slug>/state.yaml` with the feature slug substituted
2. **Checks budget** — reads `.agent-calls` counter; exits gracefully if `MAX_AGENT_CALLS` is hit
3. **Runs each gate in order** — for each gate:
   - Checks `SKIP_GATES` — skips if listed
   - Reads `state.yaml` — skips if already `complete`
   - Injects runtime context into the agent prompt (base_url, test_cmd, perf budgets)
   - Calls `claude -p <agent-prompt> --model <model> --max-turns <turns>`
   - Increments the call counter
   - Reads the agent's output from `state.yaml`
   - On failure: increments loop-back counter; retries up to `MAX_LOOP_BACKS`
   - On `MAX_LOOP_BACKS` exceeded: sets `status: awaiting_human`, exits
4. **On completion** — all gates pass → state is `complete` → run `make steward FEATURE=<slug>`

### State file anatomy

```yaml
feature_slug: user-authentication
status: in_progress          # pending | in_progress | complete | awaiting_human

prd_linter:   {status: complete, confidence: 0.95}
architect:    {status: complete, confidence: 0.88}
engineer:     {status: in_progress, confidence: null}
qa:           {status: pending,     confidence: null}
ux:           {status: pending,     confidence: null}
performance:  {status: pending,     confidence: null}
cicd:         {status: pending,     confidence: null}
red_team:     {status: pending,     confidence: null}
push_to_pr:   {status: pending,     confidence: null}

loop_backs:
  prd_linter: 0
  architect: 1        # retried once — visible in make status
  engineer: 0
```

### Human intervention points

The loop pauses and sets `status: awaiting_human` when:
- A gate exceeds `MAX_LOOP_BACKS` retries
- `MAX_AGENT_CALLS` is reached
- An agent explicitly flags a decision it can't make alone

To resume after resolving the issue:
```bash
# Edit state.yaml if needed (e.g. reset a gate to pending, increase max calls)
make resume FEATURE=<slug>
# or with extended budget:
make resume FEATURE=<slug> MAX_AGENT_CALLS=75
```

---

## Knowledge Base (Self-Improvement)

Every agent has a KB domain (`kb/<domain>/`). When an agent discovers something generalizable — a pattern that worked, a pitfall to avoid, a decision rationale — it writes a learning to its domain.

The Steward agent maintains the KB:
- **Post-merge** (`make steward`): promotes feature-specific learnings to the appropriate `kb/<domain>/` file
- **Weekly pass** (`make steward-deep`): deduplicates entries, archives stale ones, audits docs for accuracy, verifies all Mermaid diagrams compile

### KB loading rule (token efficiency)

Agents always read `kb/INDEX.md` first. The index tells them which files are relevant. They load at most 2 KB files per run. They never scan the `kb/` directory directly.

This keeps context windows lean. The KB grows without making agents slower or more expensive.

### What gets promoted to KB vs stays in features/

- **Generalizable** (goes to `kb/`): "pagination with cursor tokens is faster than offset for >10k rows"
- **Feature-specific** (stays in `features/<slug>/`): "the login endpoint returns 403 for suspended accounts"

---

## Quality Gates Detail

### PRD Linter

Checks for: clear user story, acceptance criteria, non-functional requirements, out-of-scope callouts, security considerations. Returns a structured list of issues. Blocks the loop until resolved.

### Architect (Opus — runs once)

Produces an ADR covering: chosen tech stack with rationale, data models, API contracts (request/response shapes), auth/authz model, error handling strategy, deployment topology. This ADR is the contract all downstream agents work from.

### Engineer (test-first)

1. Reads the ADR
2. Writes failing tests that express the acceptance criteria
3. Implements the minimum code to make them pass
4. Refactors to SOLID principles
5. Does not delete or weaken existing tests without flagging for human review

### QA (mutation testing enforced)

1. Runs the full test suite (`TEST_CMD` or auto-detected)
2. Runs mutation testing — requires ≥70% mutation score to pass
3. Adds integration tests if gaps found
4. Mutation testing prevents "green tests that test nothing"

### Red Team (isolated)

Receives only the PRD. Never sees the implementation, the ADR, or `state.yaml`. This ensures an independent adversarial review uncorrupted by knowledge of what was built. Looks for: auth bypass, injection, data exposure, insecure defaults, broken access control.

### Performance

Runs k6 load tests against `BASE_URL`. Enforces the budgets set in `.factory.env`. Also checks frontend bundle size if applicable. Fails and loops back if budgets are exceeded.

---

## Security Notes

- **Dev/prod separation**: Agents only have access to the development environment. `BASE_URL` points to local dev server. Never point it at production.
- **Secret scanning**: The pre-commit hook (`scripts/hooks/secret-scan.sh`) blocks commits containing API keys, passwords, or tokens.
- **ANTHROPIC_API_KEY must be unset**: If set, all Claude usage bills to the API account instead of the Max plan. `install.sh` warns loudly if it's set.
- **Agent file changes require human approval**: The Steward writes proposals to `features/steward-proposals/` but never auto-applies changes to agent files or `CLAUDE.md`.

---

## Tips

**Writing a good PRD**

The PRD Linter will catch issues, but a complete PRD up front saves loop-backs. Include: user story, acceptance criteria, edge cases, non-functional requirements (latency, concurrency), out-of-scope items, and any security constraints.

**Skipping gates for the right reasons**

- `SKIP_GATES=ux` — backend service, no UI
- `SKIP_GATES=performance` — early prototype, performance not yet a concern
- Never skip `red_team` for anything user-facing or data-handling

**When the loop pauses**

Read `features/<slug>/state.yaml`. The loop-backs section shows which gate is stuck and how many times it retried. Often the fix is in the PRD (add a missing requirement) rather than in the code. Edit the PRD or state, then `make resume`.

**Extending the budget mid-run**

```bash
make resume FEATURE=<slug> MAX_AGENT_CALLS=75
```

**Running a quick feature (skipping slow gates)**

```bash
make run FEATURE=<slug> SKIP_GATES=performance,red_team MAX_AGENT_CALLS=20
```

**Weekly maintenance**

```bash
make steward-deep   # run once a week to keep KB healthy
```

---

## Credits

AutoCodeEngine uses [Claude Code](https://docs.anthropic.com/claude-code) subagents, the `claude -p` headless API, and the [Claude Max plan](https://claude.ai). Performance testing uses [k6](https://k6.io). GitHub integration uses the [gh CLI](https://cli.github.com).
