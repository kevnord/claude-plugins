---
name: audit-testability
description: Audit a repository for test quality and coverage and produce a scored assessment. Use when evaluating test coverage, test quality, or testing health.
---

# Audit: Testability

## Purpose

Evaluates the testing health of the codebase. Checks test coverage breadth, test quality, isolation, naming, fixture patterns, and CI integration. A high score means the codebase has thorough, well-structured tests; a low score means testing is weak or absent.

## Evaluation Criteria

### Test Coverage Presence & Breadth
- **What to look for:** Existence of unit, integration, and e2e tests
- **How to assess:** Glob for test directories and files. Count test files vs source files.
  - Good: Tests for most modules, multiple test types present
  - Bad: Few or no tests found
- **Severity:** CRITICAL if no tests exist; MAJOR if fewer than 20% of source files have tests; MINOR if 20-50% coverage

### Test Quality
- **What to look for:** Behavior-based assertions vs implementation-based assertions
- **How to assess:** Read a sample of test files. Check for outcome assertions vs mock call counts.
  - Good: Tests assert on outcomes and behavior (e.g., "should return user when found")
  - Bad: Tests primarily assert on mock call counts or internal implementation details
- **Severity:** MAJOR if the majority of tests assert on implementation; MINOR if only some tests do

### Test Isolation
- **What to look for:** Shared state between tests, ordering dependencies
- **How to assess:** Check for global state, shared fixtures, and tests that fail when run in isolation.
  - Good: Each test has independent setup and teardown, no shared mutable state
  - Bad: Tests fail when run alone, shared database state, test ordering dependencies
- **Severity:** MAJOR if shared mutable state is pervasive; MINOR if cleanup is inconsistent

### Test Naming & Organization
- **What to look for:** Clear, descriptive test names and logical grouping
- **How to assess:** Check naming patterns across describe/it blocks and test functions.
  - Good: Names follow a pattern like "should [behavior] when [condition]"
  - Bad: Names like "test1", "testFoo", or bare function names with no context
- **Severity:** MINOR for consistently poor naming; SUGGESTION for inconsistent organization

### Fixture/Factory Patterns
- **What to look for:** How test data is created and managed
- **How to assess:** Look for builder or factory helpers vs inline hardcoded data throughout test files.
  - Good: Shared factories or builders with realistic, meaningful data
  - Bad: Magic numbers, meaningless strings like "foo" or "bar", duplicated inline setup
- **Severity:** MINOR if no factories or builders exist; SUGGESTION for minor inline data issues

### CI Integration
- **What to look for:** Tests running automatically in the CI pipeline
- **How to assess:** Check CI config files for test steps and merge-blocking rules.
  - Good: Tests run on every pull request and block merging on failure
  - Bad: No CI configured, or tests exist but are not part of the pipeline
- **Severity:** MAJOR if tests exist but are not run in CI; MINOR if CI exists but does not block merges on failure

## Scoring Rubric

Uses the global finding-count thresholds as defaults:
- 9-10: No CRITICAL or MAJOR findings, at most 2 MINOR
- 7-8: No CRITICAL, at most 2 MAJOR
- 5-6: No CRITICAL, at most 5 MAJOR
- 3-4: 1 CRITICAL or more than 5 MAJOR
- 1-2: Multiple CRITICAL findings

A repository with zero tests is automatically scored CRITICAL regardless of other criteria.

## Sampling Strategy

**Scoped audit:** If a scoped file list is provided in the subagent prompt, restrict ALL sampling and analysis to only those files. Skip criteria that cannot be evaluated from the scoped files and note them as "not assessed (out of scope)."

1. Use Glob to find all test files and CI config files (e.g., `.github/workflows/`, `.circleci/`, `jest.config.*`, `pytest.ini`)
2. Count test files vs source files to estimate coverage breadth
3. Deep-read 10-15 test files sampled across different modules and test types
4. Set confidence:
   - **High**: Analyzed 15+ test files covering multiple modules and reviewed CI config
   - **Medium**: Analyzed 10-14 test files or CI config was absent or unclear
   - **Low**: Analyzed fewer than 10 test files or the test suite is very sparse

## References (future)

This skill supports future tech-specific criteria via the `references/` directory. At v2, matching `references/<stack>.md` files will be loaded automatically to add language-specific test tooling checks.

## Output Schema

Return results as structured JSON:

```json
{
  "category": "testability",
  "score": 6,
  "confidence": "High",
  "findings": [
    {
      "severity": "MAJOR",
      "description": "Only 18% of source files have corresponding test files; large portions of the service layer are untested",
      "location": "src/services/",
      "recommendation": "Add unit tests for all service classes, prioritizing those with business-critical logic"
    }
  ],
  "top_recommendations": [
    "Increase test coverage from 18% to at least 60%, starting with the service and repository layers",
    "Replace mock-call-count assertions in src/services/__tests__/ with behavior-based outcome assertions",
    "Add a test step to the CI pipeline that blocks pull request merges on test failure"
  ],
  "summary": "Testing is present but thin -- coverage is below 20%, several tests assert on implementation details, and CI does not block merges on failure"
}
```
