---
name: audit-api-design
description: Audit a repository's API design quality and produce a scored assessment. Use when evaluating endpoint naming, REST conventions, versioning, error responses, or overall API quality.
---

# Audit: API Design

## Purpose

Evaluates the design quality of APIs exposed by the codebase. Checks endpoint naming, HTTP method usage, error response consistency, versioning, validation, documentation, and collection patterns. Skipped automatically for repos with no API surface. A high score means the API is well-designed and developer-friendly; a low score means the API is inconsistent or poorly documented.

## Evaluation Criteria

### Endpoint Naming Conventions
- **What to look for:** Consistent URL patterns across all routes
- **How to assess:** Grep for route definitions. Check for plural nouns, kebab-case, and absence of verbs in paths.
  - Good: `/users`, `/orders/{id}/items`
  - Bad: `/getUser`, `/Order_items`
- **Severity:** MAJOR if pervasive inconsistency across the API surface; MINOR if isolated to a few endpoints

### HTTP Method Usage
- **What to look for:** Proper REST semantics for each operation type
- **How to assess:** Check that GET is read-only, POST creates, PUT/PATCH updates, and DELETE removes resources.
  - Good: Correct mapping of HTTP verbs to CRUD operations
  - Bad: GET with side effects, POST used for all operations
- **Severity:** MAJOR for GET with side effects; MINOR for misuse without side effects

### Error Response Consistency
- **What to look for:** Uniform error format across all endpoints
- **How to assess:** Read error handling in controllers. Check for a consistent schema and proper status codes.
  - Good: Consistent schema (e.g., RFC 7807), proper HTTP status codes used throughout
  - Bad: Different error formats per endpoint, returning 200 for errors
- **Severity:** MAJOR if no consistent format exists; MINOR if mostly consistent with isolated deviations

### API Versioning
- **What to look for:** A clear strategy for handling breaking changes
- **How to assess:** Look for `/v1/`, `/v2/` path segments or `Accept-Version` header handling.
  - Good: Clear versioning strategy consistently applied
  - Bad: No versioning of any kind
- **Severity:** MINOR if none present (may not yet be needed); SUGGESTION if versioning would clearly be beneficial

### Request/Response Validation
- **What to look for:** Defined and enforced input/output contracts
- **How to assess:** Check request body validation logic and presence of DTOs or schema definitions.
  - Good: Schemas defined and validated on all inputs and outputs
  - Bad: No validation, untyped request bodies accepted
- **Severity:** MAJOR if no validation present; MINOR if validation is incomplete or inconsistently applied

### API Documentation
- **What to look for:** OpenAPI/Swagger specification or equivalent
- **How to assess:** Glob for `openapi.yml`, `swagger.json`, or similar. Assess whether docs are auto-generated or manually maintained and whether they are current.
  - Good: Spec present and auto-generated from code; kept in sync
  - Bad: No documentation, or documentation is stale and does not reflect actual endpoints
- **Severity:** MAJOR if no docs exist for a public-facing API; MINOR for internal-only APIs

### Collection Patterns
- **What to look for:** Pagination, filtering, and sorting on list endpoints
- **How to assess:** Check list endpoints for pagination parameters and response envelope.
  - Good: Consistent pagination strategy (e.g., cursor or offset) applied across all collection endpoints
  - Bad: Endpoints that return unbounded result sets with no pagination
- **Severity:** MAJOR if no pagination on large collections; MINOR if pagination exists but is applied inconsistently

## Scoring Rubric

Uses the global finding-count thresholds as defaults:
- 9-10: No CRITICAL or MAJOR findings, at most 2 MINOR
- 7-8: No CRITICAL, at most 2 MAJOR
- 5-6: No CRITICAL, at most 5 MAJOR
- 3-4: 1 CRITICAL or more than 5 MAJOR
- 1-2: Multiple CRITICAL findings

No domain-specific adjustments for API Design.

## Sampling Strategy

**Scoped audit:** If a scoped file list is provided in the subagent prompt, restrict ALL sampling and analysis to only those files. Skip criteria that cannot be evaluated from the scoped files and note them as "not assessed (out of scope)."

1. Grep for route/endpoint definitions (e.g., `@Get`, `@Post`, `router.get`, `app.get`, `path:`) across the codebase
2. Read a representative sample of controllers or route handlers to assess naming, method usage, and error handling
3. Glob for OpenAPI or Swagger files (`openapi.yml`, `openapi.yaml`, `swagger.json`, `swagger.yaml`)
4. Deep-read sample handlers to evaluate validation logic and response shapes
5. Set confidence:
   - **High**: Analyzed 20+ route definitions covering multiple controllers or modules
   - **Medium**: Analyzed 10-19 route definitions or coverage limited to a subset of the API surface
   - **Low**: Analyzed fewer than 10 routes or the codebase exposes very few endpoints

## References (future)

This skill supports future tech-specific criteria via the `references/` directory. At v2, matching `references/<stack>.md` files will be loaded automatically to add framework-specific API design checks.

## Output Schema

Return results as structured JSON:

```json
{
  "category": "api-design",
  "score": 6,
  "confidence": "High",
  "findings": [
    {
      "severity": "MAJOR",
      "description": "List endpoints /users and /products return unbounded result sets with no pagination parameters",
      "location": "src/controllers/users-controller.ts:22, src/controllers/products-controller.ts:15",
      "recommendation": "Add cursor- or offset-based pagination to all collection endpoints and document the pagination envelope"
    }
  ],
  "top_recommendations": [
    "Add pagination to all list endpoints to prevent unbounded result sets",
    "Standardize error responses to a single schema (e.g., RFC 7807) across all controllers",
    "Add or generate an OpenAPI specification to document the public API surface"
  ],
  "summary": "Moderate API design quality -- naming and HTTP method usage are consistent but missing pagination on collection endpoints, inconsistent error formats, and no OpenAPI documentation reduce developer-friendliness"
}
```
