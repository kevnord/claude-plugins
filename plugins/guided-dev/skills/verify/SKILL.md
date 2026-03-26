---
name: verify
description: Verify each acceptance criterion against the implementation with concrete evidence. Use when checking requirements, verifying implementation, or confirming acceptance criteria are met.
---

# Verify

## Purpose

Systematically checks each acceptance criterion from the intake phase against the actual implementation. Produces a pass/fail checklist with concrete evidence for each criterion, and identifies what needs fixing before the task can be considered complete.

## Process

### 1. Retrieve Acceptance Criteria

Recall the acceptance criteria from the intake summary. List them explicitly before beginning verification.

### 2. Verify Each Criterion

For each acceptance criterion, perform a concrete check:

- **Code-based criteria** — Use `Read` to examine the relevant code. Verify the logic matches the requirement. Trace the code path end-to-end where possible.
- **Test-based criteria** — If tests exist for the criterion, use `Bash` to run them and confirm they pass.
- **UI-based criteria** — If a dev server is running, use Playwright MCP to demonstrate the criterion via live interaction:
  1. Navigate to the relevant page or route
  2. Perform the interaction described by the criterion (click buttons, fill forms, navigate)
  3. Assert that the expected behavior occurs (element visibility, text content, navigation)
  4. Take a screenshot as evidence using `browser_take_screenshot` and save to `docs/guided-dev/verify-screenshot-NN.png` (NN = zero-padded criterion number)
  5. Report: "Criterion verified: [action taken], [result observed]. Screenshot: docs/guided-dev/verify-screenshot-NN.png"
  If no dev server is available, fall back to checking component code and note that live verification was not performed.
- **API-based criteria** — If a server is running, use `Bash` with `curl` to hit endpoints and verify response shapes, status codes, and payloads. Otherwise, check route definitions, handlers, and test results.
- **Configuration-based criteria** — Read config files and verify values are set correctly.

### 3. Produce Verification Checklist

Output in this format:

```
## Acceptance Criteria Verification

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | <criterion text> | [PASS] or [FAIL] | <specific evidence — file:line, test result, Playwright screenshot path, or observation> |
| 2 | <criterion text> | [PASS] or [FAIL] | <specific evidence> |
| ... | | | |

### Summary
- **Passed:** N of M
- **Failed:** N of M
```

### 4. Handle Failures

If any criteria fail:

```
### Failed Criteria — Fixes Needed

1. **<Criterion>** — [FAIL]
   - **What's wrong:** <specific description of the gap>
   - **Suggested fix:** <concrete steps to fix>
   - **Files to change:** `<path>`, `<path>`

Would you like me to fix these issues before proceeding?
```

If the user agrees, fix each issue and re-verify the failed criteria.

### 5. Final Status

Once all criteria pass (or the user explicitly accepts the remaining failures):

```
All acceptance criteria verified. Ready to proceed to quality review.
```

### Guidelines

- **Evidence is required** — never mark a criterion as PASS without pointing to specific code, test output, or configuration that proves it.
- **Be thorough** — check the actual behavior, not just that the code exists. A function that exists but has a bug is a FAIL.
- **Re-verify after fixes** — if you fix a failing criterion, verify it again before marking it PASS.
