---
name: audit-security
description: Audit a repository for security vulnerabilities and produce a scored assessment. Use when scanning for secrets exposure, injection vectors, auth issues, or dependency vulnerabilities.
---

# Audit: Security

## Purpose

Evaluates the security posture of the codebase. Checks for secrets exposure, dependency vulnerabilities, input validation, auth patterns, injection vectors, security headers, and sensitive data handling. A high score means the codebase follows security best practices; a low score means exploitable vulnerabilities or risky patterns exist.

## Evaluation Criteria

### Secrets/Credentials in Code
- **What to look for:** Grep for `password=`, `secret=`, `api_key=`, `token=`, AWS keys (`AKIA`), private keys. Check for committed `.env` files and `.gitignore` coverage.
- **How to assess:** Scan the entire codebase for secret patterns. Check `.gitignore` to confirm `.env` and secrets files are excluded.
  - Good: No secrets in source; `.env` excluded via `.gitignore`; secrets sourced from environment or vault
  - Bad: Hardcoded credentials, API keys in source files, `.env` committed to the repo
- **Severity:** CRITICAL if secrets found in source; MAJOR if `.env` committed without `.gitignore`

### Dependency Vulnerabilities
- **What to look for:** Read lockfiles (`package-lock.json`, `yarn.lock`, `Gemfile.lock`, etc.), check for known vulnerable patterns, check for audit tooling (`dependabot`, `renovate`).
- **How to assess:** Inspect lockfiles for pinned versions and check for vulnerability scanning configuration files.
  - Good: Audit tooling configured (Dependabot/Renovate), lockfiles present, dependencies kept current
  - Bad: No scanning configured, outdated lockfiles, known vulnerable package versions
- **Severity:** CRITICAL if vulnerable packages present; MAJOR if no scanning configured

### Input Validation
- **What to look for:** Grep for request handlers and check whether validation occurs before use.
- **How to assess:** Read controllers and API entry points to verify schema validation is applied before business logic.
  - Good: Schema validation libraries used (Joi, Zod, FluentValidation); all inputs validated at the boundary
  - Bad: Raw request params used directly without sanitization or validation
- **Severity:** MAJOR if no validation on public endpoints; MINOR if validation is partial or inconsistent

### Auth/Authz Patterns
- **What to look for:** Look for auth middleware, JWT validation, and role-based access checks. Verify all routes are protected.
- **How to assess:** Trace route definitions and middleware chains. Confirm that user-data endpoints require authentication and authorization.
  - Good: Auth middleware applied globally or explicitly to all protected routes; role checks enforced
  - Bad: Auth missing or inconsistently applied; unauthenticated access to user data endpoints
- **Severity:** CRITICAL if no auth on user data endpoints; MAJOR if auth is inconsistent across routes

### Injection Vectors
- **What to look for:** Grep for string concatenation in queries, unsanitized HTML rendering, and `exec`/`spawn` calls with user input.
- **How to assess:** Read database query code and template rendering logic for direct user-input interpolation.
  - Good: Parameterized queries, ORM usage, auto-escaping templating engines
  - Bad: String interpolation in SQL, `innerHTML` set with user data, shell commands built from user input
- **Severity:** CRITICAL for each injection vector found

### Security Headers/CORS
- **What to look for:** Look for CORS configuration, Content Security Policy (CSP), HSTS, and `X-Frame-Options` headers.
- **How to assess:** Read server and middleware configuration for header definitions. Check CORS origin allowlists.
  - Good: Restrictive CORS origin allowlist, CSP configured, HSTS and `X-Frame-Options` set
  - Bad: CORS allowing all origins (`*`), no CSP, missing security headers
- **Severity:** MAJOR if CORS is wide open; MINOR if security headers are incomplete

### Sensitive Data Handling
- **What to look for:** Grep for logging statements that include user data. Check for encryption-at-rest configuration.
- **How to assess:** Read logging setup and data persistence layers for PII or sensitive field exposure.
  - Good: PII excluded from logs, sensitive fields encrypted at rest, data minimization practiced
  - Bad: User emails, passwords, or tokens written to logs; sensitive data stored unencrypted
- **Severity:** MAJOR if PII appears in logs; MINOR if encryption at rest is not verified

## Scoring Rubric

Domain-specific scoring applies: a single secrets-in-code or injection vector finding is auto-CRITICAL, capping the score at 4 maximum.

- 9-10: No CRITICAL or MAJOR findings, at most 2 MINOR
- 7-8: No CRITICAL, at most 2 MAJOR
- 5-6: No CRITICAL, at most 5 MAJOR
- 3-4: 1 CRITICAL or more than 5 MAJOR
- 1-2: Multiple CRITICAL findings

## Sampling Strategy

**Scoped audit:** If a scoped file list is provided in the subagent prompt, restrict ALL sampling and analysis to only those files. Skip criteria that cannot be evaluated from the scoped files and note them as "not assessed (out of scope)."

1. Use Grep to scan the entire codebase for secret patterns (`password=`, `AKIA`, `BEGIN PRIVATE KEY`, etc.)
2. Use Glob to locate lockfiles and dependency manifests; inspect for vulnerability scanning configuration
3. Deep-read controllers, route definitions, and auth middleware files
4. Grep for injection-risk patterns (string interpolation in queries, `innerHTML`, `exec`/`spawn`)
5. Read CORS and security header middleware configuration
6. Set confidence:
   - **High**: Scanned full codebase for secret/injection patterns and deep-read auth and controller layers
   - **Medium**: Scanned most of the codebase but coverage of some modules or languages is limited
   - **Low**: Analyzed fewer than 10 files or significant portions of the codebase were inaccessible

## References (future)

This skill supports future tech-specific criteria via the `references/` directory. At v2, matching `references/<stack>.md` files will be loaded automatically to add language-specific security checks.

## Output Schema

Return results as structured JSON:

```json
{
  "category": "security",
  "score": 3,
  "confidence": "High",
  "findings": [
    {
      "severity": "CRITICAL",
      "description": "AWS access key hardcoded in source file (AKIA...)",
      "location": "src/config/aws.ts:12",
      "recommendation": "Remove the key immediately, rotate it in AWS IAM, and source credentials from environment variables or a secrets manager"
    }
  ],
  "top_recommendations": [
    "Remove all hardcoded credentials and rotate any exposed keys",
    "Add Dependabot or Renovate to automate dependency vulnerability scanning",
    "Apply input validation (Zod/Joi) at all public API entry points before passing data to business logic"
  ],
  "summary": "Critical security posture -- one hardcoded AWS key and two SQL injection vectors require immediate remediation before any further deployment"
}
```
