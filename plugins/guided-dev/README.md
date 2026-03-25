# Guided Dev

An agent-powered development workflow plugin for Claude Code that guides tasks through codebase exploration, architecture design, implementation, code review, and verification using parallel specialist agents.

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
Phase 2 — Explore      Parallel code-explorer agents map the codebase
Phase 3 — Design       Parallel code-architect agents propose competing architectures
Phase 4 — Implement    Execute the chosen plan, write and run tests
Phase 5 — Review       Parallel code-reviewer agents with confidence filtering
Phase 6 — Verify       Check each acceptance criterion with evidence
Phase 7 — PR           Create a pull request with acceptance criteria checklist
```

### Human Gates

- **Hard gates (always stop):** Intake (approve acceptance criteria) and Design (pick architecture approach)
- **Conditional gates (stop only if issues found):** Review and Verify

## Arguments

| Flag | Description | Default |
|------|-------------|---------|
| `<task description>` | Inline task description (positional) | Prompted in Phase 1 |
| `--resume <phase>` | Resume from a specific phase | Start from Phase 1 |
| `--skip-review` | Skip the code review phase | Off |
| `--no-pr` | Stop after verification, skip PR creation | Off |

### Resume Values

`intake`, `explore`, `design`, `implement`, `review`, `verify`, `pr`

## Usage Examples

```bash
# Start a new workflow with a task description
/guided-dev Fix the pagination bug in the search results page

# Resume from implementation after a context reset
/guided-dev --resume implement

# Skip code review for a well-defined task
/guided-dev --skip-review Add a health check endpoint at /health

# Full workflow without PR creation
/guided-dev --no-pr Prototype the new dashboard layout

```

## Agents

| Agent | Focus | Model | Dispatched In |
|-------|-------|-------|---------------|
| `code-explorer` | Trace execution paths, map architecture, document dependencies | Sonnet | Phase 2 (2-3 in parallel) |
| `code-architect` | Design implementation blueprints with competing philosophies | Sonnet | Phase 3 (2-3 in parallel) |
| `code-reviewer` | Bug detection, DRY, conventions with confidence scoring (>= 80) | Sonnet | Phase 5 (3 in parallel) |

## Skills

| Skill | Purpose |
|-------|---------|
| `intake` | Requirement gathering and acceptance criteria collection |
| `verify` | Acceptance criteria verification with evidence |

## How It Works

The `/guided-dev` command acts as an orchestrator that dispatches specialist agents for codebase exploration, architecture design, and code review, while delegating to skills for requirement intake and acceptance verification. Cross-cutting rules enforce consistency:

- **Phase tracking** — each phase is announced; ask "where are we?" at any time
- **Pause on ambiguity** — Claude stops and asks rather than guessing
- **Playwright for UI** — browser-based verification for UI tasks
- **Walkthrough on demand** — ask for a walkthrough of changes at any point
