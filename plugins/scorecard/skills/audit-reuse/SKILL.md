---
name: audit-reuse
description: Audit a repository for code reuse and produce a scored assessment. Use when evaluating code duplication, copy-paste patterns, or DRY principle adherence.
---

# Audit: Reuse

## Purpose

Evaluates how well the codebase avoids duplication and leverages shared code. Measures code duplication, copy-paste patterns, shared utility usage, library adoption, and internal API reuse. A high score means code is DRY and shared effectively; a low score means duplicated logic creates maintenance risk.

## Evaluation Criteria

### Code Duplication
- **What to look for:** Near-identical code blocks across files
- **How to assess:** Grep for distinctive patterns that appear in multiple files. Deep-read files that share similar signatures or logic.
  - Good: Shared utilities are extracted and referenced from a single location
  - Bad: The same logic appears in 3+ places with no shared abstraction
- **Severity:** MAJOR if >5 duplications are found; MINOR if 1-5 duplications are found

### Copy-Paste Patterns
- **What to look for:** Same logic repeated with slight variations (different variable names, minor structural tweaks)
- **How to assess:** Look for similar function names and structural patterns across modules. Search for naming conventions that suggest cloning (e.g., `processA`/`processB` with identical bodies).
  - Good: Variations are handled via parameterized shared functions
  - Bad: Functions like `copyFoo`/`copyBar` exist with near-identical implementations
- **Severity:** MAJOR if pervasive across the codebase; MINOR if isolated to one or two modules

### Shared Utility Usage
- **What to look for:** Whether common operations (string manipulation, date formatting, error handling) are centralized or reimplemented inline across modules
- **How to assess:** Check for `utils/`, `helpers/`, or `shared/` directories. Grep for inline reimplementations of operations that could be centralized.
  - Good: Common operations live in centralized utilities and are imported where needed
  - Bad: Each module reimplements the same helper logic independently
- **Severity:** MAJOR if no shared utility layer exists; MINOR if shared utilities exist but are underutilized

### Library Adoption
- **What to look for:** Hand-rolled implementations of problems already solved by established libraries (custom HTTP clients, date parsing, validation logic, etc.)
- **How to assess:** Check dependency manifests (`package.json`, `build.gradle`, `requirements.txt`) against what the code actually does. Look for custom implementations of well-known problem domains.
  - Good: Well-known, maintained libraries are used for standard problem domains
  - Bad: Custom solutions exist for problems with established library support
- **Severity:** MINOR for each instance of reinventing standard tooling; MAJOR if custom crypto or auth logic is hand-rolled

### Internal API/Module Reuse
- **What to look for:** Whether modules share types, interfaces, and components across boundaries or duplicate them in isolation
- **How to assess:** Check for shared type definitions, exported interfaces, and cross-module imports. Look for siloed modules that redefine the same contracts.
  - Good: Shared contracts (types, interfaces, components) are defined once and imported across modules
  - Bad: Each module defines its own version of the same data shapes or UI components
- **Severity:** MINOR if modules are siloed; SUGGESTION if sharing is mostly in place but a few gaps remain

## Scoring Rubric

Uses the global finding-count thresholds as defaults:
- 9-10: No CRITICAL or MAJOR findings, at most 2 MINOR
- 7-8: No CRITICAL, at most 2 MAJOR
- 5-6: No CRITICAL, at most 5 MAJOR
- 3-4: 1 CRITICAL or more than 5 MAJOR
- 1-2: Multiple CRITICAL findings

No domain-specific adjustments for Reuse.

## Sampling Strategy

**Scoped audit:** If a scoped file list is provided in the subagent prompt, restrict ALL sampling and analysis to only those files. Skip criteria that cannot be evaluated from the scoped files and note them as "not assessed (out of scope)."

1. Use Glob to find all source code files (exclude tests, generated code, vendor/node_modules)
2. Use Grep to find duplicate function signatures and similar code patterns across modules
3. Deep-read files that appear duplicated or share suspiciously similar naming
4. Check dependency manifests to assess library adoption
5. Set confidence:
   - **High**: Analyzed 20+ files covering multiple directories and modules
   - **Medium**: Analyzed 10-19 files or coverage limited to a subset of the codebase
   - **Low**: Analyzed fewer than 10 files or the codebase has very few source files

## References (future)

This skill supports future tech-specific criteria via the `references/` directory. At v2, matching `references/<stack>.md` files will be loaded automatically to add language-specific reuse checks.

## Output Schema

Return results as structured JSON:

```json
{
  "category": "reuse",
  "score": 6,
  "confidence": "High",
  "findings": [
    {
      "severity": "MAJOR",
      "description": "Date formatting logic is reimplemented inline in 7 different modules instead of using a shared utility",
      "location": "src/orders/format.ts, src/reporting/dates.ts, src/notifications/helpers.ts (and 4 others)",
      "recommendation": "Extract date formatting into a centralized utility in src/utils/dates.ts and import it across modules"
    }
  ],
  "top_recommendations": [
    "Consolidate duplicated date and string formatting logic into a shared utils layer",
    "Replace hand-rolled HTTP retry logic with an established library (e.g., axios-retry or ky)",
    "Extract shared TypeScript interfaces for common data shapes into a src/types/ module"
  ],
  "summary": "Moderate reuse -- shared utilities exist but are inconsistently adopted, and several modules reimplement the same logic independently"
}
```
