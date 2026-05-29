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

All config lives in `.factory.env` (gitignored). See `.factory.env.example` for all options.

**Models**
```bash
MODEL_HAIKU=claude-haiku-4-5
MODEL_SONNET=claude-sonnet-4-5
MODEL_OPUS=claude-opus-4-6
```

**Loop controls**
```bash
MAX_LOOP_BACKS=3     # retries per gate before pausing for human input
MAX_AGENT_CALLS=50   # hard ceiling on total agent calls per feature run
```

**Project settings**
```bash
BASE_URL=http://localhost:3000    # k6 load tests target
TEST_CMD=                         # leave empty for auto-detection
SKIP_GATES=ux,performance         # skip gates not relevant to your project
```

Any variable can be overridden per-run:
```bash
make run FEATURE=auth MAX_AGENT_CALLS=30 SKIP_GATES=ux
```

---

## Knowledge Base

Two-tier system — engine KB lives here; project KB lives in your repo.

- **Engine KB** (`AutoCodeEngine/kb/`) — generalizable patterns across any project. Steward opens PRs here when learnings apply beyond one codebase.
- **Project KB** (`your-repo/kb/`) — codebase-specific knowledge. Committed to your repo, never pushed to the engine.

Run `make steward-deep` weekly to deduplicate and prune stale entries.
