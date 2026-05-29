# AI Dev Factory — Core Rules

> Auto-loaded every turn — keep this file lean. Changes require human approval (Steward writes proposals).

## Principles

1. **Simplest thing that satisfies PRD + tests** — the tiebreak for every dispute.
2. **SOLID + YAGNI** — implement only what the PRD requires; no gold-plating.
3. **Test-first** — no implementation without a failing test first.
4. **Test integrity is sacred** — no test deletion or assertion-weakening without explicit human sign-off.
5. **State lives in files + git** — agents are stateless; `features/<slug>/state.md` is the memory.
6. **Log assumptions** — never silently guess; write to `features/<slug>/assumptions.md` with a confidence score (0.0–1.0). Confidence < 0.7 requires human review before proceeding.
7. **Knowledge compounds** — generalizable learnings go to `kb/<domain>/`; feature-specific facts stay in `features/`.


## Self-Improvement (every agent, on completion)

Read `kb/INDEX.md`. If you learned something that generalizes beyond this task, append to `kb/<your-domain>/`:
```
## Title
Explanation (max 150 words).
**When to use**: ...  **Trade-offs**: ...
```
Then update `kb/INDEX.md`. Never promote feature-specific facts.

## KB Loading Rule

Always read `kb/INDEX.md` first. Load at most 2 specific files from it. Never scan a whole directory.

## What Agents Must NOT Do

- Delete or weaken tests without human sign-off
- Access prod credentials or prod environment
- Modify their own role file or `CLAUDE.md` — Steward writes proposals; human applies them
- Exceed the 3-iteration loop-back ceiling — escalate to human instead
- Promote feature-specific facts to `kb/` — only generalizable how-to knowledge belongs there
