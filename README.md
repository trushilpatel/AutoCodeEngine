# AutoCodeEngine

An AI-powered development engine that turns a PRD into production-ready code. A pipeline of specialized agents handles architecture, engineering, testing, security, performance, and deployment — retrying on failure, escalating to humans only when necessary. Every completed feature feeds learnings back into the engine.

Built on [Claude Code](https://docs.anthropic.com/claude-code).

---

## How It Works

```
PRD.md
  │
  ▼
┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│  PRD Linter │ → │  Architect  │ → │  Engineer   │ → │     QA      │
└─────────────┘   └─────────────┘   └─────────────┘   └─────────────┘
                                                               │
┌─────────────┐   ┌─────────────┐   ┌─────────────┐          │
│  Push-to-PR │ ← │   CI/CD     │ ← │  Red Team   │          │
└─────────────┘   └─────────────┘   └─────────────┘          │
                                                               ▼
                        ┌─────────────┐   ┌─────────────────────────┐
                        │  Performance│ ← │          UX             │
                        └─────────────┘   └─────────────────────────┘
```

State is tracked per-feature in `features/<slug>/state.yaml`. Each agent reads it, does its work, and writes results back. The loop advances gates, retries on failure (up to `MAX_LOOP_BACKS`), and pauses for human review only when it can't proceed.

---

## Agents

| Agent | Model | Role |
|-------|-------|------|
| **PRD Linter** | Haiku | Validates PRD completeness before any code work |
| **Architect** | Opus | Produces ADR: tech stack, data models, API contracts, security model |
| **Engineer** | Sonnet | Writes tests first, then implements to make them pass |
| **QA** | Sonnet | Full test suite + mutation testing (≥70% threshold) |
| **UX** | Haiku | Reviews UI/API ergonomics, accessibility, error messages |
| **Performance** | Sonnet | k6 load tests against `BASE_URL`; enforces p95/p99/error-rate budgets |
| **CI/CD** | Haiku | Sets up or validates CI pipeline |
| **Red Team** | Sonnet | Security review from PRD only — no implementation context |
| **Push-to-PR** | Haiku | Creates branch, commits, pushes, opens GitHub PR |
| **Steward** | Haiku | Post-merge KB ingestion; classifies learnings into project vs engine KB |

---

## File Structure

```
AutoCodeEngine/
├── install.sh                    ← one-time setup
├── factory.mk                    ← Makefile interface
├── .factory.env.example          ← copy to .factory.env and edit
├── claude-agents/                ← agent definitions
├── scripts/
│   ├── run-feature.sh            ← main orchestration loop
│   ├── run-steward.sh            ← post-merge KB ingestion
│   ├── show-status.sh
│   ├── show-budget.sh
│   └── hooks/                    ← pre-commit/pre-push hooks
├── templates/
│   ├── PRD.md
│   └── state-minimal.yaml
└── kb/                           ← engine-level knowledge base
    └── INDEX.md

your-repo/
├── tools/autocode/               ← AutoCodeEngine submodule
├── .claude/agents/               ← installed by install.sh
├── .factory.env                  ← your config (gitignored)
├── Makefile                      ← includes tools/autocode/factory.mk
├── kb/                           ← project-specific knowledge base
└── features/<slug>/
    ├── PRD.md
    └── state.yaml
```

---

## Setup

### Git submodule (recommended)

```bash
git submodule add https://github.com/trushilpatel/AutoCodeEngine tools/autocode
bash tools/autocode/install.sh
cp tools/autocode/.factory.env.example .factory.env
echo 'include tools/autocode/factory.mk' >> Makefile
```

After cloning on another machine:
```bash
git submodule update --init
bash tools/autocode/install.sh
```

### Prerequisites

| Tool | Purpose |
|------|---------|
| `claude` CLI | Runs agents |
| `gh` CLI | Opens GitHub PRs — `brew install gh && gh auth login` |
| `k6` | Performance load tests — `brew install k6` |
| `python3` + `pyyaml` | YAML state management — `pip3 install pyyaml` |

---

## Usage

```bash
# Create a PRD from template
make new FEATURE=user-authentication

# Edit the PRD
$EDITOR features/user-authentication/PRD.md

# Run the full pipeline
make run FEATURE=user-authentication

# Monitor progress
make status FEATURE=user-authentication
make list

# Resume after interruption
make resume FEATURE=user-authentication

# Post-merge: classify learnings into KB
make steward FEATURE=user-authentication
```

---

## Configuration

All config lives in `.factory.env` (gitignored, never committed). Copy the example and edit:

```bash
cp tools/autocode/.factory.env.example .factory.env
```

Any variable can be overridden per-run without editing the file:

```bash
make run FEATURE=auth MAX_AGENT_CALLS=20 SKIP_GATES=ux,performance
```

---

### Models

| Variable | Default | Used by |
|----------|---------|---------|
| `MODEL_HAIKU` | `claude-haiku-4-5` | prd_linter, ux, cicd, push_to_pr, steward |
| `MODEL_SONNET` | `claude-sonnet-4-5` | engineer, qa, performance, red_team |
| `MODEL_OPUS` | `claude-opus-4-6` | architect (called once per feature) |

---

### Loop limits

| Variable | Default | Meaning |
|----------|---------|---------|
| `MAX_LOOP_BACKS` | `3` | Retries allowed per gate before the loop pauses for human input |
| `MAX_AGENT_CALLS` | `50` | Hard ceiling on total agent calls per feature run — a clean run uses ~11–15 |

---

### Gates

Each gate maps to one agent. Use `SKIP_GATES` to bypass gates not relevant to your project type.

| Gate | Model | What it does |
|------|-------|--------------|
| `prd_linter` | Haiku | Validates PRD completeness before any code work starts |
| `architect` | Opus | Produces ADR: data models, API contracts, security model |
| `engineer` | Sonnet | TDD — writes failing tests first, then implements to pass them |
| `qa` | Sonnet | Full test suite + mutation testing (≥70% threshold) |
| `ux` | Haiku | Reviews UI/API ergonomics, accessibility, error messages |
| `performance` | Sonnet | k6 load tests against `BASE_URL`; enforces p95/p99/error budgets |
| `cicd` | Haiku | Sets up or validates CI pipeline |
| `red_team` | Sonnet | Security review from PRD only — no implementation context |
| `push_to_pr` | Haiku | Creates branch, commits, pushes, opens GitHub PR |

**Common presets:**

```bash
SKIP_GATES=                          # run everything — recommended for production features
SKIP_GATES=performance,red_team      # fast iteration — saves ~6–8 agent calls
SKIP_GATES=ux                        # backend-only features
SKIP_GATES=ux,performance            # API-only or CLI features
SKIP_GATES=performance,red_team,cicd # early prototype
```

---

### Performance budgets

Only enforced when the `performance` gate runs. Units: milliseconds for latency, ratio for error rate, KB for bundle size.

| Variable | Default | Meaning |
|----------|---------|---------|
| `PERF_P95_MS` | `300` | 95th percentile response time ceiling (ms) |
| `PERF_P99_MS` | `1000` | 99th percentile response time ceiling (ms) |
| `PERF_ERROR_RATE` | `0.01` | Max HTTP error rate under load (1%) |
| `PERF_BUNDLE_KB` | `20` | Frontend JS bundle size limit (KB) |

---

### Per-agent turn limits

Uncomment in `.factory.env` to cap how many turns a specific agent can take. Useful if one agent keeps hitting its ceiling.

```bash
# TURNS_PRD_LINTER=5
# TURNS_ARCHITECT=15
# TURNS_ENGINEER=20
# TURNS_QA=20
# TURNS_UX=10
# TURNS_PERFORMANCE=15
# TURNS_CICD=6
# TURNS_RED_TEAM=25
# TURNS_PUSH_TO_PR=8
# TURNS_STEWARD=15
```

---

## Knowledge Base

Two-tier system — engine KB lives here; project KB lives in your repo.

- **Engine KB** (`AutoCodeEngine/kb/`) — generalizable patterns across any project. Steward opens PRs here when learnings apply beyond one codebase.
- **Project KB** (`your-repo/kb/`) — codebase-specific knowledge. Committed to your repo, never pushed to the engine.

Run `make steward-deep` weekly to deduplicate and prune stale entries.
