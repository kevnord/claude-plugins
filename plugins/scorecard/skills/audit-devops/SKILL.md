---
name: audit-devops
description: Audit a repository for DevOps readiness and produce a scored assessment. Use when evaluating CI/CD pipelines, containerization, deployment readiness, or infrastructure as code.
---

# Audit: DevOps

## Purpose

Evaluates the deployment and operations readiness of the codebase. Checks CI/CD configuration, container quality, environment management, infrastructure as code, build reproducibility, and deployment documentation. A high score means the codebase can be deployed reliably; a low score means deployment is risky or manual.

## Evaluation Criteria

### CI/CD Pipeline
- **What to look for:** CI/CD configuration files present and containing functional build, test, and lint steps
- **How to assess:** Glob for `.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile`, and similar. Read discovered files to check for multi-stage pipelines with test and lint jobs.
  - Good: Multi-stage pipeline covering build, lint, test, and deploy
  - Bad: No CI/CD configuration, or a config that only runs a build step
- **Severity:** CRITICAL if no CI/CD is present; MAJOR if CI exists but test or lint steps are missing

### Container Configuration
- **What to look for:** Dockerfile quality — multi-stage builds, appropriate base images, non-root user, `.dockerignore` present
- **How to assess:** Read all discovered Dockerfiles. Check for multi-stage patterns, whether the final image runs as a non-root user, and whether a `.dockerignore` file exists.
  - Good: Multi-stage build, minimal final image, non-root user, `.dockerignore` in place
  - Bad: Single-stage build, running as root, no `.dockerignore`
- **Severity:** MAJOR per distinct anti-pattern found; MINOR if only minor optimizations are missing

### Environment Variable Management
- **What to look for:** Hardcoded URLs, hostnames, or connection strings in source code; presence of an `.env.example`
- **How to assess:** Grep for hardcoded production URLs, database hostnames, and connection strings in source files. Check whether an `.env.example` or equivalent template exists.
  - Good: All environment-specific values sourced from env vars; `.env.example` documents required keys
  - Bad: Hardcoded production URLs or connection strings committed to source
- **Severity:** MAJOR for any hardcoded production values; MINOR for committed development defaults

### Infrastructure as Code
- **What to look for:** Terraform, CloudFormation, Pulumi, or CDK definitions versioned alongside the codebase
- **How to assess:** Glob for `*.tf`, `cloudformation*.yml`, `pulumi/*`, `cdk/*`. Check whether discovered files are committed and up to date.
  - Good: IaC definitions are versioned in the repo and match the deployed infrastructure
  - Bad: Infrastructure managed manually with no IaC definitions present
- **Severity:** MINOR if no IaC is present; SUGGESTION to introduce IaC if the project is otherwise mature

### Build Reproducibility
- **What to look for:** Lockfiles committed to the repository; no floating version ranges for dependencies
- **How to assess:** Check for `package-lock.json`, `yarn.lock`, `Pipfile.lock`, `go.sum`, `Gemfile.lock`, or equivalent. Verify they are committed and not listed in `.gitignore`.
  - Good: Lockfile present and committed, pinning all transitive dependencies
  - Bad: No lockfile, or lockfile present but excluded from version control
- **Severity:** MAJOR if no lockfile exists; MINOR if a lockfile exists but is not committed

### Deployment Documentation
- **What to look for:** Deployment scripts, runbooks, or clear deploy instructions in the README
- **How to assess:** Look for deploy scripts in `scripts/`, `Makefile` targets, or a `deploy/` directory. Read the README for deployment sections.
  - Good: Clear step-by-step deployment instructions and/or scripted deploy process
  - Bad: No documentation; deployment relies on tribal knowledge
- **Severity:** MINOR if no deployment documentation exists; SUGGESTION if documentation is present but incomplete

## Scoring Rubric

Uses the global finding-count thresholds as defaults:
- 9-10: No CRITICAL or MAJOR findings, at most 2 MINOR
- 7-8: No CRITICAL, at most 2 MAJOR
- 5-6: No CRITICAL, at most 5 MAJOR
- 3-4: 1 CRITICAL or more than 5 MAJOR
- 1-2: Multiple CRITICAL findings

No CI/CD is an automatic CRITICAL finding and will cap the score at 3 regardless of other findings.

## Sampling Strategy

**Scoped audit:** If a scoped file list is provided in the subagent prompt, restrict ALL sampling and analysis to only those files. Skip criteria that cannot be evaluated from the scoped files and note them as "not assessed (out of scope)."

1. Glob for CI/CD configs (`.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile`, `azure-pipelines.yml`)
2. Glob for `Dockerfile*` and `.dockerignore` at all directory levels
3. Glob for IaC files (`*.tf`, `cloudformation*.yml`, `pulumi/*`, `cdk/*`)
4. Glob for lockfiles (`package-lock.json`, `yarn.lock`, `Pipfile.lock`, `go.sum`, `Gemfile.lock`)
5. Read each discovered file to evaluate quality and completeness
6. Read the project README and any files in `scripts/` or `deploy/` for deployment documentation
7. Grep source directories for hardcoded hostnames, URLs, and connection strings
8. Set confidence:
   - **High**: CI/CD, container, and dependency files all examined; README reviewed
   - **Medium**: Some config files missing or codebase structure limited the search
   - **Low**: Very few DevOps artifacts found; conclusions rely on absence of evidence

## References (future)

This skill supports future tech-specific criteria via the `references/` directory. At v2, matching `references/<stack>.md` files will be loaded automatically to add platform-specific DevOps checks (e.g., Kubernetes manifests for container-native stacks, SAM templates for serverless).

## Output Schema

Return results as structured JSON:

```json
{
  "category": "devops",
  "score": 6,
  "confidence": "High",
  "findings": [
    {
      "severity": "MAJOR",
      "description": "CI pipeline has no test or lint steps — only a build job is configured",
      "location": ".github/workflows/ci.yml",
      "recommendation": "Add test and lint jobs to the pipeline so regressions are caught before merge"
    }
  ],
  "top_recommendations": [
    "Add test and lint steps to the CI pipeline",
    "Switch the Dockerfile to a multi-stage build and run the process as a non-root user",
    "Commit the missing lockfile so dependency versions are reproducible across environments"
  ],
  "summary": "Moderate DevOps readiness -- CI is present but incomplete, container configuration has two anti-patterns, and deployment documentation is absent"
}
```
