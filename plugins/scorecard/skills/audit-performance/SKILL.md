---
name: audit-performance
description: Audit a repository for performance issues and produce a scored assessment. Use when evaluating N+1 queries, caching, algorithmic complexity, or performance bottlenecks.
---

# Audit: Performance

## Purpose

Evaluates performance characteristics of the codebase. Checks for N+1 query patterns, caching, hot path efficiency, bundle size, algorithmic complexity, database index usage, and memory leak patterns. A high score means the code is performance-conscious; a low score means likely performance bottlenecks exist.

## Evaluation Criteria

### N+1 Query Patterns
- **What to look for:** Database queries inside loops
- **How to assess:** Grep for DB calls in loops. Read data access layers and ORM usage.
  - Good: Batch queries, eager loading
  - Bad: Single-record queries in forEach, ORM calls inside iteration
- **Severity:** CRITICAL if found in hot paths; MAJOR elsewhere

### Caching
- **What to look for:** Presence and appropriateness of caching
- **How to assess:** Look for caching libraries, TTL settings, and cache invalidation patterns.
  - Good: Caching applied to expensive operations with appropriate TTL
  - Bad: No caching present, or caching without TTL settings
- **Severity:** MINOR if absent and may not be needed; MAJOR if expensive operations are clearly uncached

### Hot Path Efficiency
- **What to look for:** Unnecessary work in request handlers or frequently called code
- **How to assess:** Read API handlers and middleware for blocking calls, redundant computation, or synchronous I/O.
  - Good: Lean handlers, async non-blocking operations
  - Bad: Heavy computation in request handlers, synchronous file I/O, redundant processing per request
- **Severity:** MAJOR for blocking operations in async contexts; MINOR for general inefficiency

### Bundle Size (frontend)
- **What to look for:** Tree-shaking opportunities missed, lack of code splitting
- **How to assess:** Check for barrel imports and dynamic import usage. Review route-level code splitting.
  - Good: Named imports from specific modules, lazy-loaded routes
  - Bad: Importing entire libraries when only a subset is used, no code splitting
- **Severity:** MINOR per instance of unnecessary full-library import; MAJOR if no code splitting exists in a large frontend app

### Algorithmic Complexity
- **What to look for:** Nested loops or O(n²) patterns operating on non-trivial data
- **How to assess:** Grep for nested iterations (for/forEach inside for/forEach). Read flagged sections to evaluate data size context.
  - Good: Single-pass algorithms, hash map lookups replacing nested search
  - Bad: Nested loops used for searching or deduplication over unbounded data
- **Severity:** MAJOR if operating on large or unbounded data; MINOR if data is known to be small and bounded

### Database Index Usage
- **What to look for:** Schema definitions and query patterns that suggest missing indexes
- **How to assess:** Check migration files and schema definitions for index declarations on foreign keys and frequently queried columns.
  - Good: Indexed foreign keys, composite indexes on commonly filtered columns
  - Bad: Full table scans implied by unindexed columns used in WHERE clauses or joins
- **Severity:** MAJOR if unindexed columns exist on large tables; SUGGESTION for smaller or less-critical tables

### Memory Leak Patterns
- **What to look for:** Unclosed resources, event listener accumulation, retained references
- **How to assess:** Look for addEventListener without corresponding removeEventListener, subscriptions without unsubscribe, connections or streams without close/cleanup.
  - Good: Cleanup in finally blocks, useEffect return functions, or explicit teardown lifecycle
  - Bad: addEventListener without remove, database connections never closed, subscriptions that grow unbounded
- **Severity:** MAJOR for each confirmed leak pattern; MINOR for potential leaks outside hot paths

## Scoring Rubric

Uses the global finding-count thresholds as defaults:
- 9-10: No CRITICAL or MAJOR findings, at most 2 MINOR
- 7-8: No CRITICAL, at most 2 MAJOR
- 5-6: No CRITICAL, at most 5 MAJOR
- 3-4: 1 CRITICAL or more than 5 MAJOR
- 1-2: Multiple CRITICAL findings

Domain-specific adjustment: Any confirmed N+1 query pattern in a hot path is automatically escalated to CRITICAL, regardless of frequency.

## Sampling Strategy

**Scoped audit:** If a scoped file list is provided in the subagent prompt, restrict ALL sampling and analysis to only those files. Skip criteria that cannot be evaluated from the scoped files and note them as "not assessed (out of scope)."

1. Grep for database call patterns inside loop constructs to surface N+1 candidates
2. Grep for nested loop patterns (`forEach`, `for`, `map` inside similar constructs)
3. Grep for import statements importing entire libraries (e.g., `import _ from 'lodash'`)
4. Deep-read API route handlers and data access layers for hot path analysis
5. Check migration or schema files for index definitions
6. Search for event listener and subscription patterns lacking cleanup
7. Set confidence:
   - **High**: Analyzed 20+ files covering API layer, data access, and frontend modules
   - **Medium**: Analyzed 10-19 files or coverage limited to a subset of the codebase
   - **Low**: Analyzed fewer than 10 files or the codebase has very few source files

## References (future)

This skill supports future tech-specific criteria via the `references/` directory. At v2, matching `references/<stack>.md` files will be loaded automatically to add language-specific performance checks.

## Output Schema

Return results as structured JSON:

```json
{
  "category": "performance",
  "score": 6,
  "confidence": "High",
  "findings": [
    {
      "severity": "CRITICAL",
      "description": "ORM findById called inside a forEach loop when fetching related records for each order",
      "location": "src/services/order-service.ts:112",
      "recommendation": "Replace per-iteration findById with a batch query using findAllByIds and map results by ID"
    }
  ],
  "top_recommendations": [
    "Eliminate N+1 query in order-service.ts by batching the related-record lookup",
    "Add indexes on foreign key columns in the orders and line_items migration files",
    "Introduce cache with TTL for the product catalog endpoint which is queried on every request"
  ],
  "summary": "Moderate performance risk -- one confirmed N+1 in the order hot path, missing indexes on high-traffic tables, and no caching on expensive catalog queries"
}
```
