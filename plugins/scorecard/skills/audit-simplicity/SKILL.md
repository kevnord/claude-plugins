---
name: audit-simplicity
description: Audit a repository for code simplicity and produce a scored assessment. Use when evaluating code complexity, cyclomatic complexity, over-engineering, or readability.
---

# Audit: Simplicity

## Purpose

Evaluates how simple, readable, and appropriately abstracted the codebase is. Measures cyclomatic complexity, nesting depth, function length, abstraction layers, and over-engineering signals. A high score means the code is straightforward to read and modify; a low score means unnecessary complexity makes the code harder to work with.

## Evaluation Criteria

### Cyclomatic Complexity
- **What to look for:** Functions/methods with many conditional branches (if/else chains, switch statements, nested ternaries)
- **How to assess:** Scan for functions with more than 10 branches. Use Grep to find deeply nested conditionals.
  - Good: Most functions have 1-5 branches, clear linear flow
  - Bad: Functions with 10+ branches, complex boolean expressions, nested ternaries
- **Severity:** MAJOR if >5 functions exceed 10 branches; MINOR if 1-5 functions exceed 10 branches

### Nesting Depth
- **What to look for:** Code blocks nested more than 3 levels deep (nested if/for/while/try)
- **How to assess:** Use Grep to find indentation patterns suggesting deep nesting. Read flagged files to confirm.
  - Good: Maximum 3 levels of nesting, early returns to flatten logic
  - Bad: 4+ levels of nesting, arrow-shaped code, deeply nested callbacks
- **Severity:** MAJOR if pervasive (>10 instances); MINOR if isolated (1-10 instances)

### Function/Method Length
- **What to look for:** Functions longer than 50 lines
- **How to assess:** Sample source files across the codebase. Count function lengths in representative files.
  - Good: Most functions are 5-30 lines, each doing one thing
  - Bad: Functions exceeding 50 lines, multiple responsibilities per function
- **Severity:** MAJOR if >5 functions exceed 100 lines; MINOR if functions are 50-100 lines

### Abstraction Depth
- **What to look for:** Long chains of delegation where a function calls another which calls another with little logic added at each layer
- **How to assess:** Trace call chains from entry points. Count the layers before real work happens.
  - Good: 2-3 layers of abstraction with clear responsibilities at each level
  - Bad: 5+ layers of pass-through delegation, "astronaut architecture"
- **Severity:** MAJOR if systemic (most flows have 5+ layers); MINOR if isolated

### Over-Engineering Signals
- **What to look for:** Design patterns used unnecessarily (factories for one implementation, strategy pattern with one strategy, DI for things that never change), premature abstractions, excessive configuration for single-use features
- **How to assess:** Search for common patterns (Factory, Strategy, Builder, Abstract) and check if they have multiple implementations. Look for interfaces with single implementors.
  - Good: Patterns used where they provide clear value, simple code for simple problems
  - Bad: GoF patterns everywhere, interfaces with one implementation, generics where concrete types suffice
- **Severity:** MAJOR if pervasive; MINOR if isolated; SUGGESTION for borderline cases

### File Length & Single Responsibility
- **What to look for:** Files exceeding 500 lines, files that handle multiple unrelated concerns
- **How to assess:** Check file sizes across the project. Read large files to assess whether they have a single clear purpose.
  - Good: Files are 50-300 lines, each with a clear single purpose
  - Bad: Files exceeding 500 lines, mixing concerns (UI + data access, routing + business logic)
- **Severity:** MAJOR if >5 files exceed 500 lines; MINOR if 1-5 files exceed 500 lines

## Scoring Rubric

Uses the global finding-count thresholds as defaults:
- 9-10: No CRITICAL or MAJOR findings, at most 2 MINOR
- 7-8: No CRITICAL, at most 2 MAJOR
- 5-6: No CRITICAL, at most 5 MAJOR
- 3-4: 1 CRITICAL or more than 5 MAJOR
- 1-2: Multiple CRITICAL findings

No domain-specific adjustments for Simplicity.

## Sampling Strategy

**Scoped audit:** If a scoped file list is provided in the subagent prompt, restrict ALL sampling and analysis to only those files. Skip criteria that cannot be evaluated from the scoped files and note them as "not assessed (out of scope)."

1. Use Glob to find all source code files (exclude tests, generated code, vendor/node_modules)
2. Use Bash with `wc -l` on a sample of files to identify the largest files
3. Deep-read up to 20 of the largest/most complex files
4. Use Grep to scan broadly for nesting patterns (multiple levels of indentation) and long function signatures
5. Set confidence:
   - **High**: Analyzed 20+ files covering multiple directories and modules
   - **Medium**: Analyzed 10-19 files or coverage limited to a subset of the codebase
   - **Low**: Analyzed fewer than 10 files or the codebase has very few source files

## References (future)

This skill supports future tech-specific criteria via the `references/` directory. At v2, matching `references/<stack>.md` files will be loaded automatically to add language-specific complexity checks.

## Output Schema

Return results as structured JSON:

```json
{
  "category": "simplicity",
  "score": 7,
  "confidence": "High",
  "findings": [
    {
      "severity": "MAJOR",
      "description": "Function processUserData exceeds 150 lines with 12 conditional branches",
      "location": "src/services/user-service.ts:45",
      "recommendation": "Extract validation, transformation, and persistence into separate functions"
    }
  ],
  "top_recommendations": [
    "Break down the 5 largest functions (>100 lines) into smaller, focused functions",
    "Reduce nesting in src/handlers/ by using early returns and guard clauses",
    "Remove unused abstraction layers in src/factories/ (3 factories with single implementations)"
  ],
  "summary": "Moderate complexity -- most code is readable but 5 large functions and pervasive 4-level nesting in handler layer need attention"
}
```
