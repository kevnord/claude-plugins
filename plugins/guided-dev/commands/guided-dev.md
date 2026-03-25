---
description: Start an agent-powered development workflow with codebase exploration, architecture design, code review, verification, and PR creation
argument-hint: "[<task description>] [--resume <phase>] [--skip-review] [--no-pr]"
---

# Guided Dev

You are orchestrating an agent-powered development workflow that treats Claude as a senior engineer joining the team. The workflow moves through up to 7 phases: intake, codebase exploration, architecture design, implementation + testing, code review, verification, and PR creation. Follow these phases exactly.

---

## Cross-Cutting Rules

These rules apply throughout all phases:

- **Phase tracking:** At the start of each phase, announce it clearly: `"## Phase N — <Name>"`. If the user asks "where are we?", state the current phase and what's been completed.
- **Walkthrough on demand:** If the user asks for a walkthrough of the changes at any point, provide one — walk through each changed file, explain what was done and why.
- **Playwright for UI work:** If the task involves UI changes, use Playwright for browser-based verification during the verify phase.
- **Pause on ambiguity:** If at any point during implementation you encounter a decision that isn't covered by the plan or clarification, stop and ask the user rather than guessing.

---

## Phase 0: Parse Arguments

Parse `$ARGUMENTS` for the following:

- **Positional text** — everything that isn't a flag is the inline task description. Join all positional segments into one string.
- `--resume <phase>` — resume from a specific phase. Valid values: `intake`, `explore`, `design`, `implement`, `review`, `verify`, `pr`.
- `--skip-review` — skip the code review phase entirely.
- `--no-pr` — stop after verification; do not create a PR.
Store all parsed values for use throughout the workflow.

---

## Resume Logic

If `--resume` is provided:

1. Announce: `"Resuming from Phase <N> — <Name>"`
2. Before executing the target phase, re-establish context:
   - Run `git log --oneline -10` and `git diff --stat` to understand recent changes
   - Read any files that were likely modified as part of earlier phases
   - Reconstruct the task description, acceptance criteria, and key decisions from the code and git history
3. Summarize what you've reconstructed and confirm with the user before proceeding
4. Skip to the target phase

---

## Phase 1 — Intake

Announce: `"## Phase 1 — Intake"`

Invoke the `intake` skill using the `Skill` tool. If an inline task description was provided in `$ARGUMENTS`, pass it to the skill so it can skip the initial prompt.

The intake skill will:
1. Collect or acknowledge the task description
2. Gather acceptance criteria from the user — if the user doesn't provide any, the skill will generate suggested criteria from the task description and present them for the user to add/remove/edit before continuing
3. Ask for supporting materials
4. Output a structured intake summary

**HARD GATE:** The user must approve the acceptance criteria before proceeding.

Store the intake summary — it's used by every subsequent phase.

---

## Phase 2 — Explore

Announce: `"## Phase 2 — Explore"`

Dispatch 2-3 code-explorer agents in parallel using the `Agent` tool. Each agent should target a different aspect of the codebase based on the task description:

**Example agent prompts** (adapt based on the specific task):
- "Find features similar to [task] and trace through their implementation comprehensively"
- "Map the architecture, conventions, and abstractions for [relevant area], tracing through the code comprehensively"
- "Analyze the current implementation of [related subsystem or integration point], tracing through the code comprehensively"

Each agent prompt must include the task description and acceptance criteria from the intake summary. Each agent should return a list of 5-10 key files to read.

After agents return:

1. Read all files identified by agents (deduplicated, up to ~15-20 unique files) to build deep understanding.
2. Present an exploration summary covering:
   - Tech stack and project type
   - Key conventions (naming, file organization, module structure)
   - Test setup (framework, file locations, naming conventions)
   - Architecture patterns discovered
   - Relevant files with their significance
   - Recent activity relevant to the task

Store the exploration summary — it's used by subsequent phases.

---

## Phase 3 — Design

Announce: `"## Phase 3 — Design"`

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

**HARD GATE:** The user must select an approach before implementation begins.

Store the chosen plan for implementation.

### Generate ADR

After the user selects an approach, generate an Architecture Decision Record:

1. **Determine sequence number:** Run `ls docs/adr/ 2>/dev/null | grep -E '^\d{4}-.*\.md$' | sort -r | head -1 | grep -oE '^\d{4}'` to extract the highest existing sequence number. If the directory doesn't exist or is empty, start at `0001`. Otherwise parse the 4-digit number, add 1, and zero-pad to 4 digits.
2. **Derive slug:** Take the task description from the intake summary. Lowercase it, replace non-alphanumeric characters with hyphens, collapse consecutive hyphens, trim to 50 characters, and trim trailing hyphens. Store this slug — it will be reused for the acceptance record in Phase 6.
3. **Create directory:** `mkdir -p docs/adr`
4. **Write ADR** to `docs/adr/NNNN-<slug>.md` using this format:

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

---

## Phase 4 — Implement

Announce: `"## Phase 4 — Implement"`

Execute the chosen plan:

1. Work through the plan's file list methodically — create/modify files in a logical order (dependencies first, then dependents).
2. Follow existing codebase conventions discovered during exploration (naming, patterns, structure).
3. **Pause on ambiguity** — if you encounter a decision not covered by the plan, stop and ask the user. Do not guess.
4. **Write tests** — As part of implementation, create tests that directly verify the acceptance criteria. Follow the testing patterns discovered during exploration (framework, file locations, naming conventions).
5. **Run the test suite** — Execute the relevant tests using the project's test runner. If any tests fail, diagnose the issue (test bug vs. implementation bug), fix it, and re-run.
6. **Run the full suite** — If the project has a broader test suite, run it to ensure nothing was broken. Fix any regressions.
7. After completing implementation, briefly summarize what was done: which files were created/modified and the key changes in each.

---

## Phase 5 — Review

Announce: `"## Phase 5 — Review"`

**If `--skip-review` was provided:** Skip this phase entirely. Announce: `"Skipping code review (--skip-review). Moving to verification."` and proceed to Phase 6.

Otherwise:

### 1. Resolve Changed Files

Use `Bash` to get the list of changed files:

```bash
git diff HEAD --name-only
```

Filter to only files that currently exist on disk. If the list is empty, announce: `"No changes found for review. Proceeding to verification."` and proceed to Phase 6.

### 2. Dispatch Code Reviewers

Dispatch 3 code-reviewer agents in parallel using the `Agent` tool — each with a different focus area:

- **Agent 1 (Simplicity):** "Review the following changed files for simplicity, DRY violations, unnecessary complexity, and code elegance. Focus only on the listed files."
- **Agent 2 (Correctness):** "Review the following changed files for bugs, logic errors, race conditions, null/undefined handling, security vulnerabilities, and functional correctness. Focus only on the listed files."
- **Agent 3 (Conventions):** "Review the following changed files for project convention compliance, naming consistency, abstraction quality, and adherence to CLAUDE.md guidelines. Focus only on the listed files."

Each agent prompt must include: the list of changed files and instruction to use confidence threshold >= 80.

### 3. Consolidate Findings

Collect results from all agents. Deduplicate overlapping findings. Group by severity.

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

---

## Phase 6 — Verify

Announce: `"## Phase 6 — Verify"`

Invoke the `verify` skill using the `Skill` tool.

The verify skill will:
1. Retrieve acceptance criteria from the intake phase
2. Check each criterion against the implementation with concrete evidence (including test results from Phase 4)
3. Produce a pass/fail checklist

**CONDITIONAL GATE — only stops if failures are found:**

If all criteria pass: Announce `"All acceptance criteria verified."` and proceed automatically to Phase 7.

If there are failures: The verify skill will present what's wrong and suggest fixes. Allow the verify skill to fix them if the user agrees. Re-verify until all criteria pass or the user accepts the remaining state.

### Generate Acceptance Record

After the verification loop fully resolves (all criteria pass, or the user accepts the remaining state):

1. **Determine sequence number:** Run `ls docs/acceptance/ 2>/dev/null | grep -E '^\d{4}-.*\.md$' | sort -r | head -1 | grep -oE '^\d{4}'` to extract the highest existing sequence number. If the directory doesn't exist or is empty, start at `0001`. Otherwise parse the 4-digit number, add 1, and zero-pad to 4 digits.
2. **Reuse slug:** Use the same slug derived in Phase 3. If Phase 3 was skipped (e.g., `--resume implement`), derive the slug now from the task description using the same algorithm: lowercase, replace non-alphanumeric characters with hyphens, collapse consecutive hyphens, trim to 50 characters, trim trailing hyphens.
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
    | 1 | <criterion text> | PASS | <file:line, test output, or config reference> |
    | 2 | <criterion text> | FAIL | <explanation of remaining state> |

Use the *final* verification state after all re-verify cycles — not the first pass. If fixes were applied and re-verified, reflect the post-fix status. If some criteria FAIL and the user accepts the remaining state, write the record with FAIL statuses preserved.

Announce the path of the written acceptance record file, e.g.: `"Acceptance record written to docs/acceptance/0003-add-oauth-support.md"`

---

## Phase 7 — PR

Announce: `"## Phase 7 — PR"`

**If `--no-pr` was provided:** Skip this phase. Announce: `"Skipping PR creation (--no-pr). Workflow complete!"` and output the final summary.

Otherwise, create a pull request:

1. **Stage and commit** — Stage all changed files with a clear, descriptive commit message that references the task.
2. **Create a branch** — If not already on a feature branch, create one with a descriptive name (e.g., `feat/short-task-description`).
3. **Push and create PR** — Push the branch and create a PR using `gh pr create` with:
   - A clear, concise title (under 70 characters)
   - A description that includes:
     - Summary of changes
     - Acceptance criteria checklist (with checkmarks for verified items)
     - Testing summary
     - Artifacts generated (with file paths):
       - ADR: `docs/adr/NNNN-<slug>.md` (if generated this run)
       - Acceptance Record: `docs/acceptance/NNNN-<slug>.md` (if generated this run)
4. Report the PR URL to the user.

---

## Workflow Complete

After the final phase, output:

```
## Workflow Complete

### Summary
- **Task:** <brief task description>
- **Phases completed:** <list of phases run>
- **Acceptance criteria:** <N/N passed>
- **Tests:** <passed/failed/skipped>
- **Code review:** <passed / N issues fixed / skipped>
- **PR:** <URL or "skipped">
- **ADR:** <path or "skipped (resumed past Phase 3)">
- **Acceptance record:** <path or "skipped (resumed past Phase 6)">

### Files Changed
- `<path>` — <brief description of change>
- ...
```
