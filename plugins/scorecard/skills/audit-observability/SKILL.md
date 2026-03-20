---
name: audit-observability
description: Audit a repository for observability and produce a scored assessment. Use when evaluating logging, monitoring, error tracking, health checks, or production debuggability.
---

# Audit: Observability

## Purpose

Evaluates how well the codebase supports monitoring, debugging, and incident response. Checks structured logging, error tracking, health checks, metrics, distributed tracing, and log level usage. A high score means the team can diagnose production issues quickly; a low score means production problems are hard to debug.

## Evaluation Criteria

### Structured Logging
- **What to look for:** JSON logging with consistent fields across the codebase
- **How to assess:** Grep for logging library imports (winston, pino, serilog, log4j, slog). Read representative logging call sites to assess output structure.
  - Good: JSON output with consistent fields (timestamp, level, message, correlationId)
  - Bad: console.log statements, unstructured text output, ad hoc string concatenation
- **Severity:** MAJOR if no structured logging exists; MINOR if structured logging is only partially adopted

### Error Tracking
- **What to look for:** Integration with an error monitoring platform (Sentry, Datadog, Rollbar, New Relic)
- **How to assess:** Look for error tracking library imports and initialization config in app entry points and middleware.
  - Good: Error tracking configured and integrated at the application boundary
  - Bad: Errors only appear in logs with no dedicated monitoring or alerting
- **Severity:** MAJOR if no error tracking integration exists; MINOR if integration is present but not comprehensive

### Health Check Endpoints
- **What to look for:** Liveness, readiness, and/or status probe endpoints
- **How to assess:** Grep for /health, /ready, /live, and /status route registrations. Read the handlers to assess depth.
  - Good: Health endpoint that checks dependencies (database, cache, downstream services)
  - Bad: No health endpoint, or an endpoint that only returns a static 200 with no dependency checks
- **Severity:** MAJOR if no health endpoint exists; MINOR if an endpoint exists but performs no dependency checks

### Metrics/Instrumentation
- **What to look for:** Application-level metrics collection
- **How to assess:** Look for metrics library imports and usage (prometheus-client, micrometer, StatsD, OpenMetrics). Check if key business and performance metrics are instrumented.
  - Good: Key metrics instrumented (request counts, latencies, error rates, business events)
  - Bad: No application-level metrics; only infrastructure-level metrics available
- **Severity:** MINOR if no metrics instrumentation exists; SUGGESTION if instrumentation is sparse or limited to a single service

### Distributed Tracing
- **What to look for:** Correlation IDs and trace context propagation across service boundaries
- **How to assess:** Grep for X-Request-Id, traceparent, and tracestate headers. Look for OpenTelemetry, Jaeger, or Zipkin imports and configuration.
  - Good: Trace context propagated through all service calls, correlation ID present in every log entry
  - Bad: No correlation IDs, no trace propagation, logs cannot be correlated across services
- **Severity:** MAJOR if the service communicates with other services and has no trace propagation; MINOR if the service is standalone and lacks correlation IDs

### Log Level Usage
- **What to look for:** Appropriate severity levels on logging calls throughout the codebase
- **How to assess:** Read a representative sample of logging call sites. Check whether severity matches the nature of the event.
  - Good: ERROR for unrecoverable failures, WARN for degraded conditions, INFO for key business events, DEBUG for diagnostics
  - Bad: Everything logged at INFO, exceptions swallowed silently, DEBUG output left enabled in production paths
- **Severity:** MINOR if log levels are inconsistently applied; SUGGESTION for minor misuse in isolated areas

## Scoring Rubric

Uses the global finding-count thresholds as defaults:
- 9-10: No CRITICAL or MAJOR findings, at most 2 MINOR
- 7-8: No CRITICAL, at most 2 MAJOR
- 5-6: No CRITICAL, at most 5 MAJOR
- 3-4: 1 CRITICAL or more than 5 MAJOR
- 1-2: Multiple CRITICAL findings

No domain-specific adjustments for Observability.

## Sampling Strategy

**Scoped audit:** If a scoped file list is provided in the subagent prompt, restrict ALL sampling and analysis to only those files. Skip criteria that cannot be evaluated from the scoped files and note them as "not assessed (out of scope)."

1. Grep for logging library imports and logging call sites to assess structure and level usage
2. Read application entry points and middleware for error tracking and metrics initialization
3. Check route definitions and handlers for health check endpoints
4. Grep for tracing headers and OpenTelemetry/Jaeger/Zipkin imports to assess distributed tracing
5. Set confidence:
   - **High**: Analyzed 20+ files covering entry points, routes, services, and middleware
   - **Medium**: Analyzed 10-19 files or coverage limited to a subset of the codebase
   - **Low**: Analyzed fewer than 10 files or the codebase has very few source files

## References (future)

This skill supports future tech-specific criteria via the `references/` directory. At v2, matching `references/<stack>.md` files will be loaded automatically to add language-specific observability checks.

## Output Schema

Return results as structured JSON:

```json
{
  "category": "observability",
  "score": 5,
  "confidence": "High",
  "findings": [
    {
      "severity": "MAJOR",
      "description": "No structured logging -- application uses console.log throughout with no consistent fields",
      "location": "src/",
      "recommendation": "Adopt a structured logging library (e.g. pino or winston) and emit JSON with timestamp, level, message, and correlationId on every log entry"
    }
  ],
  "top_recommendations": [
    "Replace console.log calls with a structured logging library configured to emit JSON",
    "Add a /health endpoint that verifies database and cache connectivity before returning 200",
    "Integrate Sentry or Datadog for error tracking so unhandled exceptions trigger alerts"
  ],
  "summary": "Observability is underdeveloped -- no structured logging, no error tracking integration, and no health endpoints make production incidents difficult to diagnose"
}
```
