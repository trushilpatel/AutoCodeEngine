# AI Dev Factory — Architecture

## The Loop

One feature at a time. One active branch. Sequential gates. State lives in git. Agents are stateless.

```mermaid
flowchart TD
    HUMAN([👤 Human\nwrites PRD]) --> LINT[PRD Linter\nhaiku]
    LINT -->|FAIL| HUMAN
    LINT -->|PASS| ARCH[Architect\nopus]
    ARCH -->|Low confidence\nor ambiguous| HUMAN
    ARCH -->|ADR written| ENG[Engineer\nsonnet]
    ENG --> QA[QA\nsonnet]
    QA -->|Mutation < 70%| ENG
    QA -->|PASS| UX[UX\nhaiku→sonnet]
    UX -->|P0/P1 found| ENG
    UX -->|PASS| PERF[Performance\nsonnet]
    PERF -->|k6 threshold breach| ENG
    PERF -->|PASS| CICD[CI/CD\nhaiku]
    CICD --> RED[Red Team\nsonnet]
    RED -->|P0 found| HUMAN
    RED -->|P1 found| ENG
    RED -->|PASS| PR[Push-to-PR\nhaiku]
    PR --> HUMAN2([👤 Human\nreviews PR])
    HUMAN2 -->|Merge| STEW[Steward\nhaiku]
    STEW --> KB[(Knowledge\nBase)]
```

---

## State Machine (per feature)

```mermaid
stateDiagram-v2
    [*] --> prd_lint
    prd_lint --> architect : PASS
    prd_lint --> awaiting_human : FAIL / ambiguous
    architect --> engineer : complete
    architect --> awaiting_human : low_confidence
    engineer --> qa : complete
    qa --> engineer : mutation_score < 0.70
    qa --> ux : PASS
    ux --> engineer : P0/P1 found
    ux --> performance : PASS
    performance --> engineer : budget_breach
    performance --> cicd : PASS
    cicd --> red_team : complete
    red_team --> awaiting_human : P0_found
    red_team --> engineer : P1_found
    red_team --> push_to_pr : PASS
    push_to_pr --> awaiting_human : PR_open
    awaiting_human --> [*] : human_merges
    awaiting_human --> engineer : human_feedback
```

---

## Role Roster & Model Assignments

```mermaid
graph LR
    subgraph OPUS["🔴 Opus (scarce — judgment only)"]
        A[Architect]
    end
    subgraph SONNET["🟡 Sonnet (main work)"]
        E[Engineer]
        Q[QA]
        P[Performance]
        RT[Red Team]
    end
    subgraph HAIKU["🟢 Haiku (mechanical)"]
        L[PRD Linter]
        U[UX ↑sonnet]
        C[CI/CD]
        PR[Push-to-PR]
        S[Steward]
    end
```

Escalation rule: if role returns `confidence < 0.7` → re-run at next tier. UX starts Haiku, escalates to Sonnet on second loop-back.

---

## File Structure

```
ai-dev-factory/
├── CLAUDE.md                   ← Always-loaded standards (keep lean!)
├── claude-agents/              ← Rename to .claude/agents/ in your project
│   ├── manager.md
│   ├── prd-linter.md
│   ├── architect.md
│   ├── engineer.md
│   ├── qa.md
│   ├── ux.md
│   ├── performance.md
│   ├── cicd.md
│   ├── red-team.md
│   ├── push-to-pr.md
│   └── steward.md
├── templates/
│   ├── PRD.md                  ← Copy for each new feature
│   └── state.md                ← Initialised by run-feature.sh
├── features/
│   └── <slug>/
│       ├── PRD.md              ← Human-authored, never modified by agents
│       ├── state.md            ← Case file (loop state, gate statuses)
│       ├── adr.md              ← Written by Architect
│       ├── assumptions.md      ← Running assumption log
│       ├── ux-review.md        ← Written by UX
│       ├── perf-review.md      ← Written by Performance
│       ├── red-team-findings.md← Written by Red Team
│       ├── pr-description.md   ← Written by Push-to-PR
│       └── metrics.md          ← Per-feature metrics
├── kb/                         ← Generalised how-to knowledge (owned by Steward)
│   ├── INDEX.md
│   ├── engineering/
│   ├── architecture/
│   ├── testing/
│   ├── performance/
│   ├── ux/
│   ├── cicd/
│   ├── security/
│   └── archive/
├── scripts/
│   ├── run-feature.sh          ← Main orchestrator
│   ├── run-steward.sh          ← Post-merge KB ingestion
│   ├── setup-hooks.sh          ← Install git hooks once
│   └── hooks/
│       ├── run-tests.sh        ← Stack-agnostic test runner
│       ├── run-k6.sh           ← k6 performance gate
│       └── secret-scan.sh      ← Pre-commit secret detection
├── tests/
│   └── regression/             ← Red Team writes here — permanent
└── docs/
    ├── architecture.md         ← This file
    └── onboarding.md           ← How to start a feature
```

---

## Human Interaction Model

```mermaid
sequenceDiagram
    participant H as 👤 Human (phone/laptop)
    participant L as Loop (run-feature.sh)
    participant G as Git / GitHub

    H->>G: Push PRD.md to feature/<slug>
    H->>L: ./scripts/run-feature.sh (or cloud session)
    loop Feature loop
        L-->>L: Agents run sequentially
        alt Decision needed
            L->>G: Write decision_request to state.md
            L-->>H: Notification (GitHub mobile)
            H->>G: Write human_response to state.md
            H->>L: ./run-feature.sh --resume
        end
    end
    L->>G: gh pr create
    G-->>H: PR notification
    H->>G: Review + approve + merge
    H->>L: ./scripts/run-steward.sh <slug>
```

Human receives a notification and the loop pauses only at:
1. PRD lint failure (ambiguous requirement)
2. Architect low confidence / ambiguous PRD
3. Gate loop-back ceiling (3 failures)
4. Red Team P0 security finding
5. PR is open and ready for review

Everything between a clear PRD and a green PR runs autonomously.

---

## Quality Gates Summary

| Gate | Hard Condition | Enforced By |
|------|---------------|-------------|
| PRD Lint | No ambiguous/untestable criteria | prd-linter agent |
| Assumption Review | confidence ≥ 0.7 or human-approved | manager agent |
| Test Suite | All tests green, no deletions/weakenings | engineer + qa hook |
| Mutation Score | ≥ 70% | qa agent |
| UX | P0/P1 count = 0 | ux agent |
| Performance | k6 thresholds met (p95 < 300ms, errors < 1%) | performance + k6 hook |
| Red Team | P0 count = 0 | red-team agent |
| PR Approval | Human approved | GitHub |

---

## Anti-Gaming Controls

The biggest failure mode of an AI loop: the Engineer goes green by deleting tests or weakening assertions. Three controls prevent this:

1. **QA's test integrity check** — `git diff main` on test files, flags any removed assertion
2. **Mutation testing gate** — ≥ 70% mutation score; easy to pass green tests, hard to game mutations
3. **Human sign-off rule** — any test deletion or assertion weakening escalates to human, no exceptions

---

## The Knowledge Base Compact

Two rules that keep the KB from becoming a swamp:

1. **Generalises, or stays in the feature folder.** "How to handle optimistic locking in PostgreSQL" → KB. "Feature X uses table users" → feature folder only.
2. **Archive, never delete.** Stale content moves to `kb/archive/<date>_<reason>.md`. Hard deletions require human sign-off.

The Steward runs after every merge (for ingestion) and on a weekly scheduled pass (for hygiene). It writes proposals for agent file changes — it never applies them unilaterally.
