# guided-dev v2.3.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove manual flags, add auto-scaling, design evaluation, testability gates, and Playwright-grounded review/verification to the guided-dev plugin.

**Architecture:** All changes are to markdown prompt files — no runtime code. The orchestrator command (`guided-dev.md`) gets the bulk of changes. Two skills (`intake`, `verify`) get targeted additions. Supporting files (plugin.json, README, infographic) get updated to match.

**Tech Stack:** Markdown with YAML frontmatter (Claude Code plugin format), SVG for infographic.

**Spec:** `docs/superpowers/specs/2026-03-25-guided-dev-v2.3.0-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `commands/guided-dev.md` | Modify | Orchestrator — phases, flags, auto-scaling, design eval |
| `skills/intake/SKILL.md` | Modify | Add testability gate after AC approval |
| `skills/verify/SKILL.md` | Modify | Add Playwright demonstration evidence path |
| `.claude-plugin/plugin.json` | Modify | Version bump 2.2.0 → 2.3.0 |
| `README.md` | Modify | Update docs to match new interface |
| `infographic.svg` | Modify | Update to v2.3.0 visuals |
| `infographic.png` | Regenerate | Screenshot from SVG |

All paths are relative to `plugins/guided-dev/`.

---

### Task 1: Update guided-dev.md — Frontmatter, Phase 0, Cross-cutting Rules, Resume Logic

**Files:**
- Modify: `plugins/guided-dev/commands/guided-dev.md:1-55`

- [ ] **Step 1: Replace frontmatter (lines 1-4)**

Replace the current frontmatter with:

```markdown
---
description: Start an agent-powered development workflow with codebase exploration, architecture design, code review, verification, and PR creation
argument-hint: "[<task description>] [--resume <phase>] [--no-pr]"
---
```

- [ ] **Step 2: Replace Phase 0 section (lines 24-41)**

Replace Phase 0 with:

```markdown
## Phase 0: Parse Arguments

Parse `$ARGUMENTS` for the following:

- **Positional text** — everything that isn't a flag is the inline task description. Join all positional segments into one string.
- `--resume <phase>` — resume from a specific phase. Valid values: `intake`, `explore`, `design`, `implement`, `review`, `verify`, `pr`.
- `--no-pr` — stop after verification; do not create a PR.

Store all parsed values for use throughout the workflow.

Run `mkdir -p docs/guided-dev` to ensure the artifact directory exists.
```

- [ ] **Step 3: Update Resume Logic (lines 44-55)**

Replace the resume artifact list to include the new `design-evaluation.md` artifact:

```markdown
## Resume Logic

If `--resume` is provided:

1. Announce: `"Resuming from Phase <N> — <Name>"`
2. Before executing the target phase, re-establish context from artifact files:
   - Check which `docs/guided-dev/` artifact files exist: `intake-summary.md`, `exploration-summary.md`, `design-blueprint.md`, `design-evaluation.md`, `implementation-summary.md`, `review-findings.md`, `verification-results.md`
   - Read all existing artifact files to reconstruct context for the target phase
   - If required artifact files are missing (e.g., resuming at `implement` but no `intake-summary.md`), tell the user which artifacts are missing and suggest starting from an earlier phase
3. Summarize what you've reconstructed and confirm with the user before proceeding
4. Skip to the target phase
```

- [ ] **Step 4: Commit**

```bash
git add plugins/guided-dev/commands/guided-dev.md
git commit -m "refactor(guided-dev): simplify flags and update Phase 0/resume"
```

---

### Task 2: Update guided-dev.md — Phase 2 + Auto-Scaling Classification

**Files:**
- Modify: `plugins/guided-dev/commands/guided-dev.md:78-113` (Phase 2 section)

- [ ] **Step 1: Replace Phase 2 section**

Replace the entire Phase 2 section (from `## Phase 2 — Explore` through the `---` before Phase 3) with:

```markdown
## Phase 2 — Explore

Announce: `"## Phase 2 — Explore"`

Dispatch 1 code-explorer agent using the `Agent` tool with a combined prompt that covers all aspects: "Find features similar to [task], map the architecture, conventions, and abstractions for [relevant area], and analyze the current implementation of [related subsystems or integration points]. Trace through the code comprehensively."

The agent prompt must include the task description and acceptance criteria from the intake summary. The agent should return a list of 5-10 key files to read.

After the agent returns:

1. Read all files identified by the agent (up to ~15-20 unique files) to build deep understanding.
2. Present an exploration summary covering:
   - Tech stack and project type
   - Key conventions (naming, file organization, module structure)
   - Test setup (framework, file locations, naming conventions)
   - Architecture patterns discovered
   - Relevant files with their significance
   - Recent activity relevant to the task

Store the exploration summary — it's used by subsequent phases.

Write the exploration summary to `docs/guided-dev/exploration-summary.md`.

### Auto-Scale Classification

After writing the exploration summary, classify the task complexity to determine how subsequent phases behave. Use two signals:

1. **Acceptance criteria count** — from the intake summary (Phase 1)
2. **Key files identified** — the number of unique key files from the exploration

| Signal | Small | Medium |
|--------|-------|--------|
| Acceptance criteria | 1-5 | 6+ |
| Key files from exploration | <8 | 8+ |

**Either signal** hitting the medium threshold triggers medium mode.

| Behavior | Small | Medium |
|----------|-------|--------|
| Agents per phase (design, review) | 1 | 2-3 |
| Sprint contracts | No (single pass) | Auto-decompose |
| Max iterations (review-fix cycle) | 2 | 3 |
| ADR generation | No | Yes |
| Design evaluation | Orchestrator checklist | Evaluator agent |

Announce the classification:

> **Task complexity: [small/medium]**
> - Acceptance criteria: N
> - Key files: N
> - Mode: single-agent / multi-agent
> - Iterations: 2 / 3
```

- [ ] **Step 2: Commit**

```bash
git add plugins/guided-dev/commands/guided-dev.md
git commit -m "refactor(guided-dev): single explorer + auto-scale classification"
```

---

### Task 3: Update guided-dev.md — Phase 3 (Design)

**Files:**
- Modify: `plugins/guided-dev/commands/guided-dev.md` (Phase 3 section, lines 116-238)

- [ ] **Step 1: Replace Phase 3 section**

Replace from `## Phase 3 — Design` through the `---` before Phase 4 with:

```markdown
## Phase 3 — Design

Announce: `"## Phase 3 — Design"`

Read `docs/guided-dev/intake-summary.md` and `docs/guided-dev/exploration-summary.md` to load context.

**If medium mode:**

Dispatch 2-3 code-architect agents in parallel using the `Agent` tool. Each agent designs the feature from a different philosophy:

- **Agent 1 (Minimal changes):** "Design the simplest implementation that meets all acceptance criteria. Maximize code reuse, minimize new files and refactoring. Optimize for the smallest diff and fastest delivery."
- **Agent 2 (Clean architecture):** "Design an implementation that prioritizes maintainability and elegant abstractions. Good separation of concerns, easy to test and extend."
- **Agent 3 (Pragmatic balance):** "Design an implementation that balances speed with quality. Clean enough to maintain, lean enough to ship quickly."

Each agent prompt must include: the intake summary, exploration summary, and all acceptance criteria.

After agents return:

1. Review all approaches and form your opinion on which fits best for this specific task — consider task size, urgency, complexity, and team context.
2. Present to the user:
   - Brief summary of each agent's approach with trade-offs
   - Your recommendation with reasoning
   - Concrete differences between the approaches
3. **Ask the user which approach they prefer.** Accommodate hybrid requests (e.g., "approach 2 but with the error handling from approach 1").

**If small mode:**

Dispatch 1 code-architect agent using the `Agent` tool with the "Pragmatic balance" philosophy: "Design an implementation that balances speed with quality. Clean enough to maintain, lean enough to ship quickly."

The agent prompt must include: the intake summary, exploration summary, and all acceptance criteria.

After the agent returns:

1. Present the design to the user with a summary and trade-offs.
2. **Ask the user to approve or request changes.**

**HARD GATE:** The user must approve an approach before proceeding.

Store the chosen plan for implementation.

### Derive Slug

Derive a slug from the task description: lowercase it, replace non-alphanumeric characters with hyphens, collapse consecutive hyphens, trim to 50 characters, and trim trailing hyphens. Store this slug — it will be reused for the ADR (medium) and acceptance record (Phase 6).

### Generate ADR (medium only)

**If medium mode**, generate an Architecture Decision Record after the user selects an approach:

1. **Determine sequence number:** Run `ls docs/adr/ 2>/dev/null | grep -E '^\d{4}-.*\.md$' | sort -r | head -1 | grep -oE '^\d{4}'` to extract the highest existing sequence number. If the directory doesn't exist or is empty, start at `0001`. Otherwise parse the 4-digit number, add 1, and zero-pad to 4 digits.
2. **Create directory:** `mkdir -p docs/adr`
3. **Write ADR** to `docs/adr/NNNN-<slug>.md`:

        # NNNN. <Decision Title>

        ## Status
        Accepted

        ## Date
        YYYY-MM-DD

        ## Context
        <Task description from intake and why a design decision was needed>

        ## Options Considered

        ### Option 1: <Agent's approach name> — Minimal changes
        <Summary of agent 1's approach and trade-offs>

        ### Option 2: <Agent's approach name> — Clean architecture
        <Summary of agent 2's approach and trade-offs>

        ### Option 3: <Agent's approach name> — Pragmatic balance (if 3 agents were dispatched)
        <Summary of agent 3's approach and trade-offs>

        ## Decision
        <Which option the user chose and their rationale>

        ## Consequences
        <What becomes easier or harder, from the chosen blueprint's trade-offs>

The philosophy labels ("Minimal changes", "Clean architecture", "Pragmatic balance") come from the dispatch prompts above — the agents do not output these labels themselves. Map agent index to label when generating the ADR.

The ADR is written silently — no additional approval gate. The user already approved the decision.

Announce the path of the written ADR file, e.g.: `"ADR written to docs/adr/0003-add-oauth-support.md"`

### Write Design Blueprint

Write the chosen architecture blueprint to `docs/guided-dev/design-blueprint.md`. Include the full blueprint from the selected approach (with any hybrid modifications the user requested), the list of files to create/modify, and the build sequence.

### Sprint Planning (medium only)

**If medium mode:**

Decompose the chosen blueprint into sprints using automatic detection:

- 9-15 files OR 6-8 acceptance criteria: **2-3 sprints**.
- \>15 files OR >8 acceptance criteria: **3-5 sprints**.

For each sprint, produce a sprint contract and write it to `docs/guided-dev/sprint-contract-NN.md` (NN = zero-padded sprint number starting at 01):

    # Sprint NN: <Sprint Title>

    ## Scope
    - Files to create: `<path>`, ...
    - Files to modify: `<path>`, ...

    ## Deliverables
    1. <Concrete deliverable with file path and function/component name>
    2. ...

    ## Verification Criteria
    1. <Testable statement that can be checked after this sprint>
    2. ...

    ## Dependencies
    - Depends on: Sprint NN (if applicable)
    - Produces: <what later sprints need from this one>

Present all sprint contracts to the user for review. The user can request changes (reorder, merge, split, adjust scope). Announce: `"Sprint contracts ready. Does this breakdown look right, or would you like to adjust?"` Wait for confirmation before proceeding.

**If small mode:** Skip sprint planning. Implementation will proceed as a single pass.
```

- [ ] **Step 2: Commit**

```bash
git add plugins/guided-dev/commands/guided-dev.md
git commit -m "refactor(guided-dev): Phase 3 uses auto-scale instead of flags"
```

---

### Task 4: Add Phase 3.5 — Design Evaluation

**Files:**
- Modify: `plugins/guided-dev/commands/guided-dev.md` (insert after Phase 3, before Phase 4)

- [ ] **Step 1: Insert Phase 3.5 section**

Insert the following new section between the Phase 3 `---` and `## Phase 4 — Implement`:

```markdown
## Phase 3.5 — Design Evaluation

Announce: `"## Phase 3.5 — Design Evaluation"`

Read `docs/guided-dev/intake-summary.md`, `docs/guided-dev/exploration-summary.md`, and `docs/guided-dev/design-blueprint.md`.

**If small mode — orchestrator checklist:**

Evaluate the chosen design against these checks. No agent dispatch needed.

1. **AC coverage:** For each acceptance criterion, identify which part of the design addresses it. Flag any criterion not clearly covered.
2. **Integration risk:** Based on the exploration summary, are there existing patterns or subsystems the design interacts with that could cause friction?
3. **Edge cases:** Are there obvious edge cases (empty states, error paths, concurrent access) not addressed?
4. **Scope proportionality:** Is the design proportional to the task, or does it introduce unnecessary abstraction?

**If medium mode — evaluator agent:**

Dispatch a single evaluator agent using the `Agent` tool (subagent_type: `feature-dev:code-reviewer`) with this prompt:

> "You are reviewing an architecture design, not code. Evaluate this design against the acceptance criteria and codebase context. Be skeptical — your job is to find gaps, not praise the design.
>
> Check:
> 1. Does every acceptance criterion have a clear implementation path in the design?
> 2. Are there integration risks with existing code patterns found during exploration?
> 3. Are edge cases covered (empty states, error paths, concurrent access)?
> 4. Is the scope proportional to the task, or does it over-engineer?
> 5. Are there simpler alternatives the architect missed?
>
> Return a list of issues found with suggested fixes, or explicitly state 'No issues found' if the design is sound."

The agent receives: the full intake summary, exploration summary, and chosen design blueprint.

**For all modes:**

Write evaluation results to `docs/guided-dev/design-evaluation.md`:

```
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

**CONDITIONAL GATE — only stops if issues are found:**

If all checks pass: Announce `"Design evaluation passed. Proceeding to implementation."` and continue to Phase 4.

If issues are found: Present them to the user with suggested fixes. The user can:
- Request design changes (loop back to Phase 3 architect or make targeted edits to the blueprint)
- Accept the design as-is and proceed

Update `docs/guided-dev/design-evaluation.md` with the final result.
```

- [ ] **Step 2: Commit**

```bash
git add plugins/guided-dev/commands/guided-dev.md
git commit -m "feat(guided-dev): add Phase 3.5 design evaluation"
```

---

### Task 5: Update guided-dev.md — Phase 4 (Implement)

**Files:**
- Modify: `plugins/guided-dev/commands/guided-dev.md` (Phase 4 section)

- [ ] **Step 1: Replace Phase 4 section**

Replace from `## Phase 4 — Implement` through the `---` before Phase 5 with:

```markdown
## Phase 4 — Implement

Announce: `"## Phase 4 — Implement"`

Read `docs/guided-dev/intake-summary.md`, `docs/guided-dev/exploration-summary.md`, and `docs/guided-dev/design-blueprint.md` to load the full context for implementation.

**If medium mode and sprint contracts exist:**

### Sprint Loop

For each sprint NN:

1. Announce: `"### Sprint NN — <Sprint Title>"`
2. Read the sprint contract from `docs/guided-dev/sprint-contract-NN.md`.
3. Re-read `docs/guided-dev/exploration-summary.md` and `docs/guided-dev/design-blueprint.md` to refresh context.
4. Implement only the files and deliverables listed in this sprint's contract.
5. Follow existing codebase conventions.
6. **Pause on ambiguity** — stop and ask the user.
7. Write tests that verify this sprint's verification criteria.
8. Run the tests for this sprint. Diagnose and fix failures.
9. Write a sprint completion summary to `docs/guided-dev/sprint-NN-complete.md` with: files created/modified, test results, verification criteria status (pass/fail for each).
10. If any verification criteria fail, fix and re-test before moving to the next sprint.
11. Announce: `"Sprint NN complete. N/N verification criteria passed."`

After all sprints complete:
- Run the full test suite to ensure nothing was broken across sprints. Fix any regressions.
- Briefly summarize overall implementation: which files were created/modified and the key changes in each.

**Otherwise (small mode or medium without sprints — single-pass implementation):**

Execute the chosen plan:

1. Work through the plan's file list methodically — create/modify files in a logical order (dependencies first, then dependents).
2. Follow existing codebase conventions discovered during exploration (naming, patterns, structure).
3. **Pause on ambiguity** — if you encounter a decision not covered by the plan, stop and ask the user. Do not guess.
4. **Write tests** — As part of implementation, create tests that directly verify the acceptance criteria. Follow the testing patterns discovered during exploration (framework, file locations, naming conventions).
5. **Run the test suite** — Execute the relevant tests using the project's test runner. If any tests fail, diagnose the issue (test bug vs. implementation bug), fix it, and re-run.
6. **Run the full suite** — If the project has a broader test suite, run it to ensure nothing was broken. Fix any regressions.
7. After completing implementation, briefly summarize what was done: which files were created/modified and the key changes in each.

**For all modes:**

Write the implementation summary to `docs/guided-dev/implementation-summary.md`. Include: list of files created/modified, key changes in each, and test results.
```

- [ ] **Step 2: Commit**

```bash
git add plugins/guided-dev/commands/guided-dev.md
git commit -m "refactor(guided-dev): Phase 4 uses auto-scale for sprint logic"
```

---

### Task 6: Update guided-dev.md — Phase 5 (Review + Playwright + Iterations)

**Files:**
- Modify: `plugins/guided-dev/commands/guided-dev.md` (Phase 5 section)

- [ ] **Step 1: Replace Phase 5 section**

Replace from `## Phase 5 — Review` through the `---` before Phase 6 with:

```markdown
## Phase 5 — Review

Announce: `"## Phase 5 — Review"`

### 0. Start Dev Server (if applicable)

Read `docs/guided-dev/intake-summary.md`. If the task involves UI or user-facing behavior:
1. Detect the project's dev server command (check `package.json` `scripts.dev` or `scripts.start`, or look for common alternatives).
2. Start it using `Bash` with `run_in_background`: e.g., `npm run dev`.
3. Wait briefly for the server to be ready (check with a curl to localhost).
4. Note the URL for use in reviewer agent prompts.

If the task is purely backend/library/CLI work with no web interface, skip this step. The dev server stays running through Phase 6.

### 1. Resolve Changed Files

Use `Bash` to get the list of changed files:

```bash
git diff HEAD --name-only
```

Filter to only files that currently exist on disk. If the list is empty, announce: `"No changes found for review. Proceeding to verification."` and proceed to Phase 6.

### 2. Dispatch Code Reviewers

**If medium mode:**

Dispatch 3 code-reviewer agents in parallel using the `Agent` tool — each with a different focus area:

- **Agent 1 (Simplicity):** "Review the following changed files for simplicity, DRY violations, unnecessary complexity, and code elegance. Focus only on the listed files."
- **Agent 2 (Correctness):** "Review the following changed files for bugs, logic errors, race conditions, null/undefined handling, security vulnerabilities, and functional correctness. Focus only on the listed files." If a dev server is running, add to this agent's prompt: "A dev server is running at [URL]. Use Playwright MCP tools to navigate the application, interact with UI elements, submit forms, and verify that the implemented features work correctly. Test happy paths and error paths. Report any behavioral issues you discover alongside code-level findings."
- **Agent 3 (Conventions):** "Review the following changed files for project convention compliance, naming consistency, abstraction quality, and adherence to CLAUDE.md guidelines. Focus only on the listed files."

**If small mode:**

Dispatch 1 code-reviewer agent using the `Agent` tool with a combined prompt: "Review the following changed files for simplicity, DRY violations, correctness, bugs, logic errors, race conditions, null/undefined handling, security vulnerabilities, project convention compliance, naming consistency, and adherence to CLAUDE.md guidelines. Focus only on the listed files." If a dev server is running, add: "A dev server is running at [URL]. Use Playwright MCP tools to navigate the application, interact with UI elements, and verify that the implemented features work correctly. Test happy paths and error paths. Report any behavioral issues alongside code-level findings."

**For all modes:**

Each agent prompt must include: the list of changed files and instruction to use confidence threshold >= 80.

### 3. Consolidate Findings

Collect results from all agents. Deduplicate overlapping findings. Group by severity.

Write the consolidated review findings to `docs/guided-dev/review-findings.md`. Include all findings grouped by severity, with file paths and line numbers.

### 4. Handle Findings

**CONDITIONAL GATE — only stops if issues are found:**

**If there are CRITICAL findings:**
List each one and tell the user:
> Code review found N critical issues. Fix these before verification, or type `skip` to proceed anyway.

Wait for the user's response. If they want fixes, apply them. If they type `skip`, proceed to Phase 6.

**If there are MAJOR findings (no CRITICAL):**
List them and ask:
> These MAJOR issues were found in the changed code. Fix now, or proceed to verification?

Wait for the user's response and act accordingly.

**If only MINOR/SUGGESTION findings or none:**
Announce: `"Code review passed. Proceeding to verification."` and continue to Phase 6.

### 5. Iteration Loop

After fixes are applied from step 4:

1. Re-run the relevant tests to confirm fixes.
2. Update `docs/guided-dev/implementation-summary.md` with the fixes applied.
3. Re-dispatch code reviewers (same mode as step 2) on **only the newly changed files** from the fix.
4. If new CRITICAL/MAJOR findings emerge, return to step 4 (Handle Findings). Repeat until no new issues or the iteration count reaches the auto-scaled maximum (small: 2, medium: 3, hard cap: 5).
5. Write the iteration history to `docs/guided-dev/iteration-log.md`:

        # Iteration Log

        ## Iteration 1
        - **Review findings:** N critical, N major, N minor
        - **Fixes applied:** <list>
        - **Re-review result:** <passed / N remaining>

        ## Iteration 2
        ...
```

- [ ] **Step 2: Commit**

```bash
git add plugins/guided-dev/commands/guided-dev.md
git commit -m "refactor(guided-dev): Phase 5 auto-scale + Playwright-grounded review"
```

---

### Task 7: Update guided-dev.md — Phase 6, Phase 7, Workflow Complete

**Files:**
- Modify: `plugins/guided-dev/commands/guided-dev.md` (Phase 6, 7, Workflow Complete sections)

- [ ] **Step 1: Replace Phase 6 section**

Replace from `## Phase 6 — Verify` through the `---` before Phase 7 with:

```markdown
## Phase 6 — Verify

Announce: `"## Phase 6 — Verify"`

Invoke the `verify` skill using the `Skill` tool.

The verify skill will:
1. Retrieve acceptance criteria from the intake phase
2. Check each criterion against the implementation with concrete evidence (including test results from Phase 4)
3. For UI-facing criteria when a dev server is running, use Playwright MCP to demonstrate each criterion via live interaction and capture screenshots as evidence
4. Produce a pass/fail checklist

**CONDITIONAL GATE — only stops if failures are found:**

If all criteria pass: Announce `"All acceptance criteria verified."` and proceed automatically to Phase 7.

If there are failures: The verify skill will present what's wrong and suggest fixes. Allow the verify skill to fix them if the user agrees. Re-verify until all criteria pass or the user accepts the remaining state.

### Generate Acceptance Record

After the verification loop fully resolves (all criteria pass, or the user accepts the remaining state):

1. **Determine sequence number:** Run `ls docs/acceptance/ 2>/dev/null | grep -E '^\d{4}-.*\.md$' | sort -r | head -1 | grep -oE '^\d{4}'` to extract the highest existing sequence number. If the directory doesn't exist or is empty, start at `0001`. Otherwise parse the 4-digit number, add 1, and zero-pad to 4 digits.
2. **Reuse slug:** Use the same slug derived in Phase 3.
3. **Create directory:** `mkdir -p docs/acceptance`
4. **Write acceptance record** to `docs/acceptance/NNNN-<slug>.md` using this format:

    # <Feature Name>

    ## Date
    YYYY-MM-DD

    ## Task Description
    <Task description from intake>

    ## Acceptance Criteria

    | # | Criterion | Status | Evidence |
    |---|-----------|--------|----------|
    | 1 | <criterion text> | PASS | <file:line, test output, Playwright screenshot, or config reference> |
    | 2 | <criterion text> | FAIL | <explanation of remaining state> |

Use the *final* verification state after all re-verify cycles — not the first pass. If fixes were applied and re-verified, reflect the post-fix status. If some criteria FAIL and the user accepts the remaining state, write the record with FAIL statuses preserved.

Announce the path of the written acceptance record file, e.g.: `"Acceptance record written to docs/acceptance/0003-add-oauth-support.md"`

Write the verification results to `docs/guided-dev/verification-results.md`. Include the full pass/fail checklist with evidence.

If a dev server is running, stop it now.
```

- [ ] **Step 2: Replace Phase 7 section**

Replace from `## Phase 7 — PR` through the `---` before Workflow Complete with:

```markdown
## Phase 7 — PR

Announce: `"## Phase 7 — PR"`

**If `--no-pr` was provided:** Skip this phase. Announce: `"Skipping PR creation (--no-pr). Workflow complete!"` and output the final summary.

Otherwise, create a pull request:

1. **Stage and commit** — Stage all changed files (including `docs/guided-dev/` workflow artifacts) with a clear, descriptive commit message that references the task.
2. **Create a branch** — If not already on a feature branch, create one with a descriptive name (e.g., `feat/short-task-description`).
3. **Push and create PR** — Push the branch and create a PR using `gh pr create` with:
   - A clear, concise title (under 70 characters)
   - A description that includes:
     - Summary of changes
     - Acceptance criteria checklist (with checkmarks for verified items)
     - Testing summary
     - Artifacts generated (with file paths):
       - ADR: `docs/adr/NNNN-<slug>.md` (medium mode only)
       - Acceptance Record: `docs/acceptance/NNNN-<slug>.md`
       - Workflow artifacts: `docs/guided-dev/`
4. Report the PR URL to the user.
```

- [ ] **Step 3: Replace Workflow Complete section**

Replace the Workflow Complete section with:

```markdown
## Workflow Complete

After the final phase, output:

```
## Workflow Complete

### Summary
- **Task:** <brief task description>
- **Complexity:** <small / medium>
- **Phases completed:** <list of phases run>
- **Acceptance criteria:** <N/N passed>
- **Tests:** <passed/failed/skipped>
- **Code review:** <passed / N issues fixed> (N iterations)
- **PR:** <URL or "skipped">
- **ADR:** <path or "n/a (small mode)">
- **Acceptance record:** <path>
- **Workflow artifacts:** `docs/guided-dev/`

### Files Changed
- `<path>` — <brief description of change>
- ...
```
```

- [ ] **Step 4: Commit**

```bash
git add plugins/guided-dev/commands/guided-dev.md
git commit -m "refactor(guided-dev): Phase 6/7/complete use auto-scale"
```

---

### Task 8: Update skills/intake/SKILL.md — Testability Gate

**Files:**
- Modify: `plugins/guided-dev/skills/intake/SKILL.md:40-79`

- [ ] **Step 1: Insert testability gate after the review step**

In `skills/intake/SKILL.md`, after the review step (line 50 — the paragraph ending "Only proceed once the user approves the final list.") and before `### 3. Collect Supporting Materials`, insert:

```markdown
### 2b. Testability Gate

After the user approves the acceptance criteria, evaluate each criterion for verifiability. A criterion is verifiable if it can be confirmed with at least one of: a test result, a file:line reference, a CLI output, or a Playwright interaction.

For each criterion that is not clearly verifiable, flag it and suggest a concrete alternative:

> I noticed some acceptance criteria may be hard to verify with concrete evidence. Here are suggested refinements:
>
> - **Original:** "<vague criterion>"
>   **Suggested:** "<concrete, testable version>"
> - ...
>
> These are suggestions — you can accept, modify, or keep the originals. Want me to update the criteria?

**Examples of transformations:**
- "Should be performant" → "API responds in < 500ms for typical payloads"
- "Error handling should work" → "Invalid input returns a 400 response with a descriptive error message"
- "UI should look good" → "Component renders without layout shift and matches the existing design system spacing"

This gate advises but does not block — if the user insists on keeping a vague criterion, respect their decision and proceed. Update the criteria list if the user accepts changes.
```

- [ ] **Step 2: Commit**

```bash
git add plugins/guided-dev/skills/intake/SKILL.md
git commit -m "feat(guided-dev): add testability gate to intake skill"
```

---

### Task 9: Update skills/verify/SKILL.md — Playwright Demonstration Evidence

**Files:**
- Modify: `plugins/guided-dev/skills/verify/SKILL.md:20-26`

- [ ] **Step 1: Enhance UI verification section**

In `skills/verify/SKILL.md`, replace the current `- **UI-based criteria**` bullet (line 23-24) with:

```markdown
- **UI-based criteria** — If a dev server is running, use Playwright MCP to demonstrate the criterion via live interaction:
  1. Navigate to the relevant page or route
  2. Perform the interaction described by the criterion (click buttons, fill forms, navigate)
  3. Assert that the expected behavior occurs (element visibility, text content, navigation)
  4. Take a screenshot as evidence using `browser_take_screenshot` and save to `docs/guided-dev/verify-screenshot-NN.png` (NN = zero-padded criterion number)
  5. Report: "Criterion verified: [action taken], [result observed]. Screenshot: docs/guided-dev/verify-screenshot-NN.png"
  If no dev server is available, fall back to checking component code and note that live verification was not performed.
```

- [ ] **Step 2: Update evidence format in the checklist template**

In `skills/verify/SKILL.md`, update the evidence column description in the checklist template (line 37) to include screenshots:

```markdown
| 1 | <criterion text> | [PASS] or [FAIL] | <specific evidence — file:line, test result, Playwright screenshot path, or observation> |
```

- [ ] **Step 3: Commit**

```bash
git add plugins/guided-dev/skills/verify/SKILL.md
git commit -m "feat(guided-dev): Playwright demonstration evidence in verify skill"
```

---

### Task 10: Update plugin.json + README.md

**Files:**
- Modify: `plugins/guided-dev/.claude-plugin/plugin.json`
- Modify: `plugins/guided-dev/README.md`

- [ ] **Step 1: Version bump plugin.json**

Replace the contents of `plugin.json` with:

```json
{
  "name": "guided-dev",
  "description": "Agent-powered development workflow with auto-scaling complexity, design evaluation, Playwright-grounded review, and acceptance verification",
  "version": "2.3.0"
}
```

- [ ] **Step 2: Replace README.md**

Replace the entire contents of `README.md` with:

```markdown
# Guided Dev

**v2.3.0**

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
```

- [ ] **Step 3: Commit**

```bash
git add plugins/guided-dev/.claude-plugin/plugin.json plugins/guided-dev/README.md
git commit -m "docs(guided-dev): update plugin.json and README for v2.3.0"
```

---

### Task 11: Update infographic.svg + regenerate PNG

**Files:**
- Modify: `plugins/guided-dev/infographic.svg`
- Regenerate: `plugins/guided-dev/infographic.png`

- [ ] **Step 1: Update infographic SVG**

Update the infographic to reflect v2.3.0 changes:

1. Change version badge text from `v2.2.0` to `v2.3.0`
2. Replace mode selector pills ("`Default (lean)`" / "`--full (rich)`") with auto-scale pills ("`Small (auto)`" / "`Medium (auto)`")
3. Update Phase 2 description to "Code-explorer agent maps codebase + auto-scale"
4. Remove the mode-aware agent badge from Phase 2 (always 1 agent now)
5. Add a new Phase 3.5 card between the sprint contracts section and Phase 4:
   - Circle number: "3.5" with a yellow/amber color (#f59e0b)
   - Title: "Evaluate"
   - Description: "Design evaluation catches gaps before implementation"
   - Conditional gate indicator (same style as Phase 5/6)
6. Update footer pills: replace "`--skip-review`" with "`Auto-scale`"
7. Adjust y-coordinates of Phase 4 through the end to accommodate the new Phase 3.5 card (shift everything below sprint contracts down by ~68px)
8. Update SVG height from 1160 to 1228 (adding 68px for the new card)

- [ ] **Step 2: Regenerate PNG**

Use Playwright to navigate to the SVG via a local HTTP server and take a full-page screenshot:

```bash
# Start server, navigate with Playwright, take screenshot, stop server
```

Save as `plugins/guided-dev/infographic.png`.

- [ ] **Step 3: Commit**

```bash
git add plugins/guided-dev/infographic.svg plugins/guided-dev/infographic.png
git commit -m "docs(guided-dev): update infographic for v2.3.0"
```

---

## Self-Review Checklist

- [x] **Spec coverage:** All 7 spec sections (interface simplification, auto-scaling, design evaluation, testability gate, Playwright review, live demonstration, iteration defaults) are covered by Tasks 1-11.
- [x] **Placeholder scan:** All steps contain exact content or clear instructions. No TBD/TODO.
- [x] **Type consistency:** "small mode" / "medium mode" terminology is consistent throughout. Flag references (`--full`, `--sprints`, `--max-iterations`, `--skip-review`) are removed everywhere.
- [x] **New artifact file:** `design-evaluation.md` added to Resume Logic artifact list (Task 1), README artifacts table (Task 10), and Phase 3.5 (Task 4).
