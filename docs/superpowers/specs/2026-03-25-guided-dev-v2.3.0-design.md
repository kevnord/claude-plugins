# guided-dev v2.3.0 Design Spec

**Date:** 2026-03-25
**Plugin:** `plugins/guided-dev/`
**Current version:** 2.2.0
**Target version:** 2.3.0

## Motivation

Applying patterns from Anthropic's [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) article to improve quality and simplify the interface. Key findings: generator-evaluator separation catches defects that self-evaluation misses; Playwright-grounded evaluation catches behavioral issues that code review misses; harness complexity should auto-scale rather than be user-configured.

## Summary of Changes

1. **Remove flags** — `--full`, `--sprints [N]`, `--max-iterations <N>`, `--skip-review`
2. **Add auto-scaling** — orchestrator classifies task complexity after Phase 2 and scales agents, sprints, iterations accordingly
3. **Add design evaluation** — new step between Phase 3 (Design) and Phase 4 (Implement) to catch design gaps before code is written
4. **Strengthen acceptance criteria** — testability gate in Phase 1 ensures every criterion is verifiable
5. **Strengthen evaluation with Playwright** — Phases 5 and 6 use live app interaction for behavioral grounding
6. **Raise iteration defaults** — small tasks get 2 iterations, medium tasks get 3

---

## 1. Interface Simplification

### Before (v2.2.0)

```
/guided-dev [task] [--resume <phase>] [--skip-review] [--no-pr] [--full] [--sprints [N]] [--max-iterations <N>]
```

### After (v2.3.0)

```
/guided-dev [task] [--resume <phase>] [--no-pr]
```

### Flags removed

| Flag | Reason | Replaced by |
|------|--------|-------------|
| `--full` | User shouldn't decide agent count upfront | Auto-scaling based on AC count and file count |
| `--sprints [N]` | Already had auto-detection logic | Always auto-detect; single pass for small, decompose for medium |
| `--max-iterations <N>` | Sane defaults are better than knobs | Auto-set: 2 for small, 3 for medium |
| `--skip-review` | Review is conditional and zero-cost when clean | Removed — review always runs; auto-proceeds if no issues |

### Flags kept

| Flag | Reason |
|------|--------|
| `--resume <phase>` | Essential for recovery; cannot be auto-detected |
| `--no-pr` | Explicit user intent; cannot be inferred |

### Files affected

- `commands/guided-dev.md` — Phase 0 argument parsing, all flag references throughout

---

## 2. Auto-Scaling

### When it runs

After Phase 2 (Explore) completes, the orchestrator has both the acceptance criteria count (from Phase 1) and the number of key files identified during exploration (from Phase 2). It classifies the task before entering Phase 3.

Phase 2 always uses a single explorer agent regardless of classification — the scaling decision depends on Phase 2's output, so it cannot affect Phase 2 itself. Scaling applies to Phases 3, 3.5, and 5.

### Classification

| Signal | Small | Medium |
|--------|-------|--------|
| Acceptance criteria | 1-5 | 6+ |
| Key files from exploration | <8 | 8+ |

**Either signal** hitting the medium threshold triggers medium mode. When signals conflict (e.g., 3 AC but 12 files), medium wins — it's safer to over-prepare than under-prepare.

### What scales

| Behavior | Small | Medium |
|----------|-------|--------|
| Agents per phase (design, review) | 1 | 2-3 |
| Sprint contracts | No (single pass) | Auto-decompose per existing algorithm |
| Max iterations (review-fix cycle) | 2 | 3 |
| ADR generation | No | Yes |
| Design evaluation | Orchestrator checklist | Evaluator agent |

Hard cap on iterations: 5 (unchanged, exists as safety net).

### Announcement

After classification, the orchestrator announces:

> **Task complexity: small/medium**
> - Acceptance criteria: N
> - Estimated files: N
> - Mode: single-agent / multi-agent
> - Iterations: 2 / 3

### Files affected

- `commands/guided-dev.md` — new section between Phase 2 and Phase 3; all conditional logic that previously checked `--full` / `--sprints` / `--max-iterations` now checks the auto-scaling result

---

## 3. Design Evaluation (New Phase 3.5)

### Purpose

Catch design gaps, missing AC coverage, and feasibility issues before implementation begins. This is the generator-evaluator separation applied to architecture: the architect agents (Phase 3) are generators; this step is the evaluator.

### When it runs

After the user selects an architecture in Phase 3 and before Phase 4 begins. It runs after ADR generation (if applicable) and after sprint planning (if applicable).

### Small mode — orchestrator checklist

The orchestrator itself evaluates the chosen design against a structured checklist. No additional agent is dispatched.

**Checklist:**
1. **AC coverage:** For each acceptance criterion, identify which part of the design addresses it. Flag any criterion not clearly covered.
2. **Integration risk:** Based on Phase 2 exploration, are there existing patterns or subsystems the design interacts with that could cause friction?
3. **Edge cases:** Are there obvious edge cases (empty states, error paths, concurrent access) not addressed?
4. **Scope proportionality:** Is the design proportional to the task, or does it introduce unnecessary abstraction?

If all checks pass, announce and proceed. If issues are found, present them to the user with suggested fixes. The user can accept the design as-is or request changes (loop back to architect).

### Medium mode — evaluator agent

Dispatch a single evaluator agent (using the `Agent` tool with `subagent_type: "feature-dev:code-reviewer"`) with a skeptical prompt:

> "You are reviewing an architecture design, not code. Evaluate this design against the acceptance criteria and codebase context. Be skeptical — your job is to find gaps, not praise the design. Check: (1) Does every acceptance criterion have a clear implementation path? (2) Are there integration risks with existing code? (3) Are edge cases covered? (4) Is the scope proportional to the task? (5) Are there simpler alternatives the architect missed? Return a list of issues found, or explicitly state 'No issues found' if the design is sound."

The agent receives: intake summary, exploration summary, chosen design blueprint, and all acceptance criteria.

If issues are found, present them to the user. The user decides: fix the design (loop back) or accept and proceed.

### Gate behavior

**Conditional gate** — auto-proceeds if no issues found. Stops only if the evaluator (orchestrator or agent) identifies gaps.

### Artifact

Write evaluation results to `docs/guided-dev/design-evaluation.md`:

```markdown
# Design Evaluation

## Checklist
| # | Check | Status | Notes |
|---|-------|--------|-------|
| 1 | AC coverage | PASS/FAIL | <details> |
| 2 | Integration risk | PASS/FAIL | <details> |
| 3 | Edge cases | PASS/FAIL | <details> |
| 4 | Scope proportionality | PASS/FAIL | <details> |

## Issues Found
- <issue description and suggested fix> (or "None")

## Result
Proceed / Revise design
```

### Files affected

- `commands/guided-dev.md` — new section after Phase 3's design blueprint and sprint planning, before Phase 4

---

## 4. Testability Gate on Acceptance Criteria (Phase 1 Alteration)

### Purpose

Ensure every acceptance criterion can be verified with concrete evidence in Phase 6. Prevents vague criteria from passing through and causing hand-wavy verification later.

### When it runs

After the user approves acceptance criteria in Phase 1, before the intake summary is written.

### How it works

The orchestrator evaluates each criterion against this test: **Can this criterion be confirmed with a test result, a file:line reference, a CLI output, or a Playwright interaction?**

For each criterion that fails the test, the orchestrator:
1. Flags it as not verifiable
2. Suggests a concrete alternative

**Example transformations:**
- "Should be performant" → "API responds in < 500ms for typical payloads"
- "Error handling should work" → "Invalid input returns a 400 response with a descriptive error message"
- "UI should look good" → "Component renders without layout shift and matches the existing design system spacing"

The user reviews the suggestions and accepts, modifies, or overrides. The gate does not block — it advises. If the user insists on keeping a vague criterion, that's their call.

### Files affected

- `skills/intake/SKILL.md` — add testability check after AC approval, before writing intake summary

---

## 5. Playwright-Grounded Review (Phase 5 Alteration)

### Purpose

Reviewer agents that interact with the running application catch behavioral bugs that code review alone misses.

### Current behavior (v2.2.0)

Phase 5 starts a dev server (if applicable) and passes the URL to reviewer agents, but agents primarily review code diffs.

### New behavior (v2.3.0)

When a dev server is available, reviewer agent prompts explicitly instruct Playwright-based interaction:

**Correctness reviewer prompt addition:**
> "A dev server is running at [URL]. Use Playwright MCP tools to navigate the application, interact with UI elements, submit forms, and verify that the implemented features work correctly. Test happy paths and error paths. Report any behavioral issues you discover alongside code-level findings."

**Simplicity and conventions reviewers** do not get Playwright instructions — their focus remains on code quality.

### Scope

Only applies when a dev server is available (UI/web tasks). For backend/library/CLI tasks, Phase 5 behavior is unchanged.

### Files affected

- `commands/guided-dev.md` — Phase 5 step 2 (Dispatch Code Reviewers), update the correctness reviewer prompt

---

## 6. Live Demonstration Evidence (Phase 6 Alteration)

### Purpose

For UI-facing acceptance criteria, verification backed by Playwright interaction and screenshots is stronger evidence than file:line citations.

### Current behavior (v2.2.0)

The verify skill checks criteria against the implementation with file:line references and test output.

### New behavior (v2.3.0)

When a dev server is running and a criterion involves user-facing behavior, the verify skill:
1. Uses Playwright MCP to navigate to the relevant page/component
2. Performs the interaction described by the criterion
3. Takes a screenshot as evidence
4. Reports the result: "Criterion verified: [action taken], [result observed]" with screenshot path

For non-UI criteria (data model changes, API contracts, config values), evidence remains file:line and test output.

### Example

Criterion: "Error message displays when the form is submitted empty"

Evidence (v2.2.0): `PASS — Error handling at Form.tsx:47`

Evidence (v2.3.0): `PASS — Navigated to /form, clicked Submit with all fields empty, error message "Please fill in all required fields" displayed. Screenshot: docs/guided-dev/verify-screenshot-01.png`

### Files affected

- `skills/verify/SKILL.md` — add Playwright verification path for UI criteria
- `commands/guided-dev.md` — Phase 6 section, note that dev server stays running from Phase 5

---

## 7. Iteration Defaults

### Current (v2.2.0)

- Default mode: 1 iteration (no re-review)
- `--full` mode: 2 iterations
- `--max-iterations` flag for manual override

### New (v2.3.0)

- Small tasks: 2 iterations
- Medium tasks: 3 iterations
- Hard cap: 5 (safety net, not exposed as a flag)

Iteration 1 finds real issues. Iteration 2 confirms fixes didn't introduce new problems. Iteration 3 (medium only) is the safety net for higher complexity.

### Files affected

- `commands/guided-dev.md` — Phase 5 step 5 (Iteration Loop), remove flag references, use auto-scaled value

---

## Phase Flow (v2.3.0)

```
Phase 0: Parse arguments (--resume, --no-pr only)
Phase 1: Intake + testability gate on AC [HARD GATE]
Phase 2: Explore → auto-scale classification
Phase 3: Design [HARD GATE] → ADR (medium) → sprint contracts (medium)
Phase 3.5: Design evaluation [CONDITIONAL GATE]
Phase 4: Implement (sprint loop if medium)
Phase 5: Review + Playwright grounding [CONDITIONAL GATE] → iteration loop (2 or 3 max)
Phase 6: Verify + live demonstration [CONDITIONAL GATE] → acceptance record
Phase 7: PR
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `commands/guided-dev.md` | Remove flags, add auto-scaling, add Phase 3.5, update Phase 5/6, update iteration logic |
| `skills/intake/SKILL.md` | Add testability gate after AC approval |
| `skills/verify/SKILL.md` | Add Playwright verification path for UI criteria |
| `.claude-plugin/plugin.json` | Version bump to 2.3.0 |
| `README.md` | Update arguments, phase descriptions, add auto-scaling docs |
| `infographic.svg` | Update to v2.3.0 with new phase and removed flags |
| `infographic.png` | Regenerate from SVG |

No new files need to be created (no new agents or skills — design evaluation uses existing agent types).
