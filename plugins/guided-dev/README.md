# Guided Dev

**v2.2.0**

An agent-powered development workflow plugin for Claude Code that guides tasks through codebase exploration, architecture design, implementation, code review, and verification. Defaults are tuned for small/medium tasks with single-agent efficiency — scale up to multi-agent mode with `--full` for complex work.

## Quick Start

```
/guided-dev
```

Or with an inline task description:

```
/guided-dev Add a rate limiter to the /api/users endpoint
```

## Phases

```
Phase 1 — Intake       Gather requirements and acceptance criteria
Phase 2 — Explore      Code-explorer agent(s) map the codebase
Phase 3 — Design       Code-architect agent(s) propose architecture
Phase 4 — Implement    Execute the chosen plan, write and run tests
Phase 5 — Review       Code-reviewer agent(s) with confidence filtering
Phase 6 — Verify       Check each acceptance criterion with evidence
Phase 7 — PR           Create a pull request with acceptance criteria checklist
```

### Human Gates

- **Hard gates (always stop):** Intake (approve acceptance criteria) and Design (approve architecture)
- **Conditional gates (stop only if issues found):** Review and Verify

## Arguments

| Flag | Description | Default |
|------|-------------|---------|
| `<task description>` | Inline task description (positional) | Prompted in Phase 1 |
| `--resume <phase>` | Resume from a specific phase | Start from Phase 1 |
| `--skip-review` | Skip the code review phase | Off |
| `--no-pr` | Stop after verification, skip PR creation | Off |
| `--full` | Multi-agent mode: competing architects, specialized reviewers, sprint contracts, ADR, 2 iteration max | Off |
| `--sprints [N]` | Enable sprint contracts in Phase 4; optional N forces count | Off |
| `--max-iterations <N>` | Max implement-review-fix iterations | 1 (`--full`: 2, max: 5) |

### Resume Values

`intake`, `explore`, `design`, `implement`, `review`, `verify`, `pr`

Resume reads artifact files from `docs/guided-dev/` to reconstruct context. If required artifacts are missing, the workflow will prompt you to start from an earlier phase.

## Usage Examples

```bash
# Start a new workflow with a task description
/guided-dev Fix the pagination bug in the search results page

# Full multi-agent mode for a complex feature
/guided-dev --full Add user authentication with OAuth2

# Enable sprint contracts for a large task
/guided-dev --sprints Migrate the database schema to support multi-tenancy

# Resume from implementation after a context reset
/guided-dev --resume implement

# Skip code review for a well-defined task
/guided-dev --skip-review Add a health check endpoint at /health

# Full workflow without PR creation
/guided-dev --no-pr Prototype the new dashboard layout
```

## Default vs Full Mode

| Behavior | Default | `--full` |
|----------|---------|----------|
| Phase 2 explorers | 1 agent | 2-3 agents |
| Phase 3 architects | 1 agent (pragmatic balance) | 2-3 agents (competing philosophies) |
| Phase 5 reviewers | 1 agent (combined focus) | 3 agents (specialized focuses) |
| Sprint contracts | Off | Auto-detect by task size |
| Iteration loops | 1 (fix and proceed) | 2 (re-review after fixes) |
| ADR generation | Skipped | Full (options considered) |

## Agents

| Agent | Focus | Model | Default | `--full` |
|-------|-------|-------|---------|----------|
| `code-explorer` | Trace execution paths, map architecture, document dependencies | Sonnet | 1 agent | 2-3 in parallel |
| `code-architect` | Design implementation blueprints | Sonnet | 1 agent (pragmatic) | 2-3 (competing philosophies) |
| `code-reviewer` | Bug detection, DRY, conventions with confidence scoring (>= 80) | Sonnet | 1 agent (combined) | 3 in parallel (specialized) |

## Skills

| Skill | Purpose |
|-------|---------|
| `intake` | Requirement gathering and acceptance criteria collection |
| `verify` | Acceptance criteria verification with evidence |

## Artifacts

### Decision & Acceptance Records

| Artifact | Written After | Location |
|----------|---------------|----------|
| **ADR** (Architecture Decision Record) | Phase 3 — Design (`--full` only) | `docs/adr/NNNN-<slug>.md` |
| **Acceptance Record** | Phase 6 — Verify | `docs/acceptance/NNNN-<slug>.md` |

### Workflow Artifacts (`docs/guided-dev/`)

Phase outputs written to `docs/guided-dev/` for inter-phase communication, resume, and traceability:

| File | Written By | Purpose |
|------|-----------|---------|
| `intake-summary.md` | Phase 1 | Task description, acceptance criteria, supporting materials |
| `exploration-summary.md` | Phase 2 | Tech stack, conventions, architecture patterns, key files |
| `design-blueprint.md` | Phase 3 | Chosen approach, file list, build sequence |
| `sprint-contract-NN.md` | Phase 3 | Sprint scope, deliverables, verification criteria (`--sprints`/`--full` only) |
| `implementation-summary.md` | Phase 4 | Files changed, test results |
| `sprint-NN-complete.md` | Phase 4 | Per-sprint completion status (`--sprints`/`--full` only) |
| `review-findings.md` | Phase 5 | Consolidated findings by severity |
| `iteration-log.md` | Phase 5 | Iteration history (`--max-iterations` > 1 only) |
| `verification-results.md` | Phase 6 | Pass/fail checklist with evidence |

Workflow artifacts are committed with the PR. To exclude them, add `docs/guided-dev/` to `.gitignore`.

## How It Works

The `/guided-dev` command acts as an orchestrator that dispatches specialist agents for codebase exploration, architecture design, and code review, while delegating to skills for requirement intake and acceptance verification. Cross-cutting rules enforce consistency:

- **Phase tracking** — each phase is announced; ask "where are we?" at any time
- **Pause on ambiguity** — Claude stops and asks rather than guessing
- **Artifact persistence** — every phase writes structured output to `docs/guided-dev/` for reliable inter-phase communication and resume
- **Playwright for live verification** — browser-based and API verification for user-facing tasks (auto-detects dev server, runs through Phases 5-6)
- **Walkthrough on demand** — ask for a walkthrough of changes at any point
