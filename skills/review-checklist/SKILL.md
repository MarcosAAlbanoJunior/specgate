---
name: review-checklist
description: Single compact code-review checklist (correctness, security, architecture, testing, production-readiness, spec alignment) with severity rules. Used by the specgate reviewer subagent.
user-invocable: false
---

# Review checklist

Review the diff once, through all six lenses. Report only real problems in changed code; do not restate what is fine.

## Lenses

1. **Correctness**: logic errors, off-by-one, null/empty handling, wrong conditions, unhandled edge cases, resource leaks, concurrency hazards.
2. **Security**:
   - authz/IDOR: every access to a resource checks that the caller may touch *that* resource, not just that they are logged in
   - injection: SQL/command/template/path built from input; use parameters or allowlists
   - secrets: no credentials, tokens or keys in code, logs or tests
   - input validation: type, range, size and format checked at the boundary
3. **Architecture**: follows existing layering and naming; no new dependency or abstraction without need; no logic in the wrong layer; no duplicated code that an existing helper covers.
4. **Testing**: every numbered acceptance criterion has at least one test that would fail if it were broken; tests assert behavior, not implementation; no skipped or weakened tests.
5. **Production-readiness**: errors are handled and surfaced with useful context; logs carry no sensitive data and are at a sensible level; configuration is externalized, not hard-coded; failure modes are bounded (timeouts, limits).
6. **Spec alignment**: every acceptance criterion is implemented; nothing from "out of scope" was built; no file outside the spec's affected files changed without justification.

## Severity

- `blocker`: wrong behavior, a security hole, data loss, or an unmet acceptance criterion. Must be fixed.
- `major`: likely future bug or serious maintainability or test gap. Should be fixed.
- `minor`: style, naming, small cleanups. Optional.

## Finding format

One line each: `[severity] path/to/file:LINE (lens) problem. Fix: concrete suggestion.`
Cite only lines present in the diff. If there are no findings, say `NO FINDINGS`.
