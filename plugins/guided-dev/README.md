# Guided Dev

**v2.3.1**

An agent-powered development workflow plugin for Claude Code that guides tasks through codebase exploration, architecture design, implementation, code review, and verification. The workflow auto-scales based on task complexity — small tasks get lean single-agent passes, medium tasks get multi-agent scrutiny with sprint contracts and competing architectures.

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
Phase 1   — Intake        Gather requirements and acceptance criteria (testability gate)
Phase 2   — Explore        Code-explorer agent maps the codebase + auto-scale classification
Phase 3   — Design         Code-architect agent(s) propose architecture
Phase 3.5 — Evaluate       Design evaluation catches gaps before implementation
Phase 4   — Implement      Execute the chosen plan, write and run tests
Phase 5   — Review         Code-reviewer agent(s) with Playwright-grounded evaluation
Phase 6   — Verify         Check each acceptance criterion with live demonstration evidence
Phase 7   — PR             Create a pull request with acceptance criteria checklist
```

### Human Gates

- **Hard gates (always stop):** Intake (approve acceptance criteria) and Design (approve architecture)
- **Conditional gates (stop only if issues found):** Design Evaluation, Review, and Verify

## Arguments

| Flag | Description | Default |
|------|-------------|---------|
| `<task description>` | Inline task description (positional) | Prompted in Phase 1 |
| `--resume <phase>` | Resume from a specific phase | Start from Phase 1 |
| `--no-pr` | Stop after verification, skip PR creation | Off |

### Resume Values

`intake`, `explore`, `design`, `implement`, `review`, `verify`, `pr`

Resume reads artifact files from `docs/guided-dev/` to reconstruct context. If required artifacts are missing, the workflow will prompt you to start from an earlier phase.

## Auto-Scaling

After Phase 2, the orchestrator classifies task complexity and adapts the workflow:

| Behavior | Small (1-5 AC, <8 files) | Medium (6+ AC or 8+ files) |
|----------|--------------------------|---------------------------|
| Architects | 1 agent (pragmatic) | 2-3 agents (competing philosophies) |
| Design evaluation | Orchestrator checklist | Evaluator agent |
| Sprint contracts | No (single pass) | Auto-decompose by task size |
| Reviewers | 1 agent (combined focus) | 3 agents (specialized focuses) |
| Iteration loops | 2 (review + re-check) | 3 (review + fix + safety net) |
| ADR generation | Skipped | Full (options considered) |

## Usage Examples

```bash
# Start a new workflow with a task description
/guided-dev Fix the pagination bug in the search results page

# Resume from implementation after a context reset
/guided-dev --resume implement

# Full workflow without PR creation
/guided-dev --no-pr Prototype the new dashboard layout
```

## Agents

| Agent | Focus | Used In |
|-------|-------|---------|
| `code-explorer` | Trace execution paths, map architecture, document dependencies | Phase 2 (always 1) |
| `code-architect` | Design implementation blueprints with competing philosophies | Phase 3 (1 or 2-3) |
| `code-reviewer` | Bug detection, DRY, conventions with confidence scoring (>= 80) | Phase 5 (1 or 3) |

## Skills

| Skill | Purpose |
|-------|---------|
| `intake` | Requirement gathering, acceptance criteria collection, testability gate |
| `verify` | Acceptance criteria verification with evidence (including Playwright screenshots) |

## Artifacts

### Decision & Acceptance Records

| Artifact | Written After | Location |
|----------|---------------|----------|
| **ADR** (Architecture Decision Record) | Phase 3 — Design (medium only) | `docs/adr/NNNN-<slug>.md` |
| **Acceptance Record** | Phase 6 — Verify | `docs/acceptance/NNNN-<slug>.md` |

### Workflow Artifacts (`docs/guided-dev/`)

Phase outputs written to `docs/guided-dev/` for inter-phase communication, resume, and traceability:

| File | Written By | Purpose |
|------|-----------|---------|
| `intake-summary.md` | Phase 1 | Task description, acceptance criteria, supporting materials |
| `exploration-summary.md` | Phase 2 | Tech stack, conventions, architecture patterns, key files |
| `design-blueprint.md` | Phase 3 | Chosen approach, file list, build sequence |
| `design-evaluation.md` | Phase 3.5 | Evaluation checklist, issues found, result |
| `sprint-contract-NN.md` | Phase 3 | Sprint scope, deliverables, verification criteria (medium only) |
| `implementation-summary.md` | Phase 4 | Files changed, test results |
| `sprint-NN-complete.md` | Phase 4 | Per-sprint completion status (medium only) |
| `review-findings.md` | Phase 5 | Consolidated findings by severity |
| `iteration-log.md` | Phase 5 | Iteration history |
| `verify-screenshot-NN.png` | Phase 6 | Playwright screenshots for UI criteria |
| `verification-results.md` | Phase 6 | Pass/fail checklist with evidence |

Workflow artifacts are committed with the PR. To exclude them, add `docs/guided-dev/` to `.gitignore`.

## How It Works

The `/guided-dev` command acts as an orchestrator that dispatches specialist agents for codebase exploration, architecture design, and code review, while delegating to skills for requirement intake and acceptance verification. The workflow auto-scales based on task complexity detected after exploration. Cross-cutting rules enforce consistency:

- **Phase tracking** — each phase is announced; ask "where are we?" at any time
- **Pause on ambiguity** — Claude stops and asks rather than guessing
- **Artifact persistence** — every phase writes structured output to `docs/guided-dev/` for reliable inter-phase communication and resume
- **Playwright for live verification** — browser-based and API verification for user-facing tasks (auto-detects dev server, runs through Phases 5-6)
- **Walkthrough on demand** — ask for a walkthrough of changes at any point
