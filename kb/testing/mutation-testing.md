## Mutation Testing Setup

Mutation testing inserts small "mutations" (e.g., `>` → `>=`, delete a condition) and checks whether your tests catch them. A surviving mutant = a test gap. Target: **≥ 70% mutation score**.

**When to use**: After unit tests are green. Run on the changed module only (not full codebase — too slow).

**Trade-offs / gotchas**:
- Slow on large files — scope to the diff, not the whole repo
- Some mutants are "equivalent" (semantically identical) — don't chase 100%
- A low score with high line coverage = tests exist but don't assert enough

**JavaScript / TypeScript — Stryker**:
```bash
npx stryker run --mutate "src/<module>/**" --reporters clear-text,json
# Results in reports/mutation/
```

Stryker config (`stryker.config.json`):
```json
{
  "mutate": ["src/<module>/**/*.ts", "!src/**/*.test.ts"],
  "testRunner": "jest",
  "reporters": ["clear-text", "json"],
  "thresholds": { "high": 80, "low": 70, "break": 70 }
}
```

**Python — mutmut**:
```bash
mutmut run --paths-to-mutate src/<module>/
mutmut results
# "survived" = test gap — write a test that kills it
```

**Killing a surviving mutant**: Read the mutant diff, ask "what test would fail if this mutation were real code?" Write that test. Re-run.
