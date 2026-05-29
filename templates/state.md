# Feature State — [feature-slug]

> This is the case file. Agents read from and write to this file.
> It is the single source of truth for loop state.
> Git history is the audit trail.

---

## Identity

```yaml
feature_slug: feature-name-kebab-case
prd_path: features/feature-name-kebab-case/PRD.md
branch: feature/feature-name-kebab-case
created: YYYY-MM-DD HH:MM
last_updated: YYYY-MM-DD HH:MM
status: in_progress  # in_progress | awaiting_human | complete | abandoned
```

---

## Gate Statuses

```yaml
prd_linter:
  status: pending          # pending | pass | fail
  blocking_issues: 0

architect:
  status: pending          # pending | complete | failed
  confidence: null
  adr_path: features/<slug>/adr.md

engineer:
  status: pending
  confidence: null

qa:
  status: pending
  mutation_score: null     # float 0.0–1.0
  coverage: null

ux:
  status: pending
  p0_count: null
  p1_count: null

performance:
  status: pending
  p95_ms: null
  p99_ms: null
  error_rate: null

cicd:
  status: pending

red_team:
  status: pending
  p0_count: null
  p1_count: null
  regression_tests_added: 0

push_to_pr:
  status: pending
  pr_url: null
```

---

## Loop Control

```yaml
loop_back_counts:
  prd_linter: 0
  architect: 0
  engineer: 0
  qa: 0
  ux: 0
  performance: 0
  cicd: 0
  red_team: 0

max_loop_backs: 3          # Hard ceiling — escalate to human at 3

escalations:               # Model escalations: haiku→sonnet→opus
  []

current_step: prd_linter   # Which role runs next
```

---

## Assumptions Log

> Agents append here. Human reviews any entry with confidence < 0.7.

```yaml
assumptions:
  - id: A001
    role: architect
    text: "Assumes PostgreSQL ≥14 is available"
    confidence: 0.95
    status: accepted      # accepted | needs_review | rejected
  # Add new assumptions below
```

---

## Decision Requests

> Written by agents when they need human input. Human writes response below each.

```yaml
decision_requests:
  []
  # Format:
  # - id: DR001
  #   raised_by: manager
  #   raised_at: YYYY-MM-DD HH:MM
  #   question: "Should we use Redis or in-memory cache for session state?"
  #   options:
  #     - A: Redis — durable, requires infra
  #     - B: In-memory — simpler, lost on restart
  #   recommended: B
  #   human_response: null   # Human fills this in
  #   generalises_to_kb: false
```

---

## Human Action Required

> Filled by agents when pausing for human. Check here for notifications.

```yaml
human_action_required: null
# Example when PR is ready:
# human_action_required:
#   type: pr_review
#   pr_url: https://github.com/org/repo/pull/42
#   summary: "All gates green. Please review and approve."
#   created_at: YYYY-MM-DD HH:MM
```

---

## Decision Log

> Manager writes every decision and its rationale here.

```yaml
decisions:
  []
  # Format:
  # - step: architect→engineer
  #   decided_at: YYYY-MM-DD HH:MM
  #   decision: "Proceed with pattern A"
  #   rationale: "Simpler, no new infra, prior KB precedent in kb/architecture/caching.md"
```

---

## Metrics

> Updated at each gate. Used by Steward for KB and by Manager for loop improvement.

```yaml
metrics:
  feature_slug: feature-name-kebab-case
  loop_back_total: 0
  human_interventions: 0
  escalations_total: 0
  time_to_pr: null       # minutes from start to PR open
  change_failure: null   # set post-merge if a bug was found in prod
  regression_escapes: 0  # bugs found after merge
```
