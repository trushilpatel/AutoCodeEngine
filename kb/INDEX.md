# Knowledge Base Index

> Maintained by the Steward. Update this every time you add or remove an entry.
> Format: `[Title](path) — one-line description`

---

## Engineering
_`kb/engineering/`_

- [SOLID Principles Applied](engineering/solid-principles.md) — practical examples of each SOLID rule with code patterns

## Architecture
_`kb/architecture/`_

- [ADR Template](architecture/adr-template.md) — blank ADR template with all required sections

## Testing
_`kb/testing/`_

- [Test-First Workflow](testing/test-first-workflow.md) — how to write failing tests before implementation
- [Mutation Testing Setup](testing/mutation-testing.md) — configuring Stryker/mutmut and interpreting results
- [Contract Test Patterns](testing/contract-tests.md) — how to write contract tests at module boundaries

## Performance
_`kb/performance/`_

- [k6 Patterns](performance/k6-patterns.md) — reusable k6 scripts: ramp, spike, soak tests

## UX
_`kb/ux/`_

- [UX Principles Checklist](ux/principles-checklist.md) — quick-reference checklist for UX review
- [Copy Guidelines](ux/copy-guidelines.md) — verb-first CTAs, error message patterns, empty states

## CI/CD
_`kb/cicd/`_

- [Git Hook Setup](cicd/git-hooks.md) — how to install and maintain the pre-commit and pre-push hooks
- [Local Dev Setup](cicd/local-dev.md) — standard setup-local.sh pattern

## Security
_`kb/security/`_

- [Common Vulnerabilities Checklist](security/vuln-checklist.md) — injection, auth bypass, CORS, secrets

## Archive
_`kb/archive/`_

_Empty — archived entries appear here with date and reason._

---

## How to Add an Entry

1. Write to the appropriate `kb/<domain>/<topic>.md` file
2. Add a line here under the correct domain
3. Use the format: `[Title](path) — one-line description`
4. If the domain doesn't exist yet, create the folder and add it above

## Format for KB Entries

```markdown
## <Topic Title>
<How-to explanation — max 200 words>

**When to use**: ...
**Trade-offs / gotchas**: ...
**Example**:
```code
...
```
```
