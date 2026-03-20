---
name: audit-maintainability
description: Audit a repository for maintainability and produce a scored assessment. Use when evaluating tech debt, naming clarity, code organization, or how easy a codebase is to change.
---

# Audit: Maintainability

## Purpose

Evaluates how easy the codebase is to understand, modify, and maintain over time. Checks naming clarity, file organization, dependency freshness, tech debt markers, documentation, and code style enforcement. A high score means a developer can onboard quickly and make changes confidently; a low score means the codebase is difficult to work with.

## Evaluation Criteria

### Naming Clarity
- **What to look for:** Descriptive names for variables, functions, classes, and files
- **How to assess:** Read sample files and scan for single-letter variables, ambiguous names, or generic identifiers.
  - Good: `getUserById`, `validateEmail`, `CustomerOrderRepository`
  - Bad: `x`, `temp`, `doStuff`, `data2`, `flag`
- **Severity:** MINOR per isolated file; MAJOR if poor naming is pervasive across the codebase

### File/Directory Organization
- **What to look for:** Consistent, logical structure with clear module boundaries
- **How to assess:** Check the project layout for grouping conventions (by feature, by layer, by domain). Look for misplaced files or flat directories that mix unrelated concerns.
  - Good: Predictable locations — you know where to find a controller, a model, a utility
  - Bad: Random scatter, all files at root level, no discernible grouping pattern
- **Severity:** MAJOR if no organization is apparent; MINOR if mostly organized with occasional misplaced files

### Dependency Freshness
- **What to look for:** Outdated or abandoned packages in dependency manifests
- **How to assess:** Read `package.json`, `build.gradle`, `requirements.txt`, `Gemfile`, or equivalent. Check for packages multiple major versions behind their current release or packages flagged as deprecated.
  - Good: Dependencies are reasonably current (within one major version)
  - Bad: Multiple major versions behind, deprecated packages with known replacements
- **Severity:** MAJOR for deprecated packages with security or compatibility risk; MINOR for outdated-but-functional packages

### Tech Debt Markers
- **What to look for:** High density of `TODO`, `FIXME`, or `HACK` comments
- **How to assess:** Grep for `TODO`, `FIXME`, and `HACK` across all source files. Count total occurrences and check whether any include ticket references or explanatory context.
  - Good: Few markers, each with a ticket reference or clear explanation
  - Bad: 50+ markers with no context, no owner, and no associated work items
- **Severity:** MINOR if fewer than 20 markers; MAJOR if more than 20 markers without ticket references

### Documentation
- **What to look for:** README quality and inline documentation on public APIs and complex logic
- **How to assess:** Check for README presence and whether it covers setup, usage, and architecture. Read public-facing modules for doc comments on exported functions and classes.
  - Good: README with setup instructions and usage examples; doc comments on public APIs and non-obvious logic
  - Bad: No README, no doc comments, complex algorithms with no explanation
- **Severity:** MAJOR if no README exists; MINOR if README or inline docs are incomplete

### Code Style Enforcement
- **What to look for:** Linter and formatter configuration files and CI enforcement
- **How to assess:** Look for `.eslintrc`, `.prettierrc`, `.editorconfig`, `pyproject.toml`, `rubocop.yml`, or equivalent. Check CI configuration for lint or format steps.
  - Good: Formatter and linter configured and enforced in CI pipeline
  - Bad: No tooling present, inconsistent formatting visible across files
- **Severity:** MINOR if no linter is configured; MAJOR if formatting is visibly inconsistent AND no tooling exists

## Scoring Rubric

Uses the global finding-count thresholds as defaults:
- 9-10: No CRITICAL or MAJOR findings, at most 2 MINOR
- 7-8: No CRITICAL, at most 2 MAJOR
- 5-6: No CRITICAL, at most 5 MAJOR
- 3-4: 1 CRITICAL or more than 5 MAJOR
- 1-2: Multiple CRITICAL findings

No domain-specific adjustments for Maintainability.

## Sampling Strategy

**Scoped audit:** If a scoped file list is provided in the subagent prompt, restrict ALL sampling and analysis to only those files. Skip criteria that cannot be evaluated from the scoped files and note them as "not assessed (out of scope)."

1. Read the project root for `README`, config files (`.eslintrc`, `.prettierrc`, `.editorconfig`), and dependency manifests
2. Use Grep to count `TODO`, `FIXME`, and `HACK` markers across all source files
3. Use Glob to survey the directory structure and assess organization
4. Sample source files across modules to evaluate naming clarity and inline documentation
5. Set confidence:
   - **High**: Analyzed 20+ files covering multiple directories and modules
   - **Medium**: Analyzed 10-19 files or coverage limited to a subset of the codebase
   - **Low**: Analyzed fewer than 10 files or the codebase has very few source files

## References (future)

This skill supports future tech-specific criteria via the `references/` directory. At v2, matching `references/<stack>.md` files will be loaded automatically to add language-specific maintainability checks.

## Output Schema

Return results as structured JSON:

```json
{
  "category": "maintainability",
  "score": 6,
  "confidence": "High",
  "findings": [
    {
      "severity": "MAJOR",
      "description": "47 TODO/FIXME markers found with no ticket references or explanatory context",
      "location": "src/ (multiple files)",
      "recommendation": "Triage existing markers: resolve, link to a tracking ticket, or delete stale ones"
    }
  ],
  "top_recommendations": [
    "Add a README covering project setup, configuration, and architecture overview",
    "Introduce ESLint and Prettier with CI enforcement to standardize code style",
    "Triage the 47 TODO/FIXME markers and link remaining ones to tracking tickets"
  ],
  "summary": "Below-average maintainability -- missing README, no style enforcement, and high untracked tech debt density make onboarding and safe modification difficult"
}
```
