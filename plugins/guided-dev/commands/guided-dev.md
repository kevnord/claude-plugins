---
description: Start a structured development workflow with intake, clarification, planning, implementation, verification, and PR creation
argument-hint: "[<task description>] [--resume <phase>] [--skip-clarify] [--max-questions <n>] [--no-pr] [--simplify] [--scorecard]"
---

# Guided Dev

You are orchestrating a structured development workflow that treats Claude as a senior engineer joining the team. The workflow moves through up to 7 phases: intake, clarification, planning, implementation + testing, verification, quality gate (optional), and PR creation. Follow these phases exactly.

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
- `--resume <phase>` — resume from a specific phase. Valid values: `intake`, `clarify`, `plan`, `implement`, `verify`, `scorecard`, `pr`.
- `--skip-clarify` — skip the clarification phase entirely.
- `--max-questions <n>` — override the default max of 20 clarifying questions.
- `--no-pr` — stop after verification; do not create a PR.
- `--simplify` — run `/simplify` on changed files after implementation.
- `--scorecard` — run a quality gate after verification: audits changed files across security, testability, and maintainability categories. Blocks on CRITICAL findings before creating the PR.

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
4. Explore the repository
5. Output a structured intake summary

Store the intake summary — it's used by every subsequent phase.

---

## Phase 2 — Clarify

Announce: `"## Phase 2 — Clarify"`

**If `--skip-clarify` was provided:** Skip this phase entirely. Announce: `"Skipping clarification (--skip-clarify). Moving to planning."` and proceed to Phase 3.

Otherwise, invoke the `clarify` skill using the `Skill` tool. Pass the max questions count (default 20, or the value from `--max-questions`).

The clarify skill will:
1. Analyze the intake summary for gaps and ambiguities
2. Ask targeted questions one at a time with multi-choice options
3. Track progress and respect the user's time
4. Output a clarification summary with all decisions made

Append the clarification summary to the intake context.

---

## Phase 3 — Plan

Announce: `"## Phase 3 — Plan"`

Invoke the `plan` skill using the `Skill` tool.

The plan skill will:
1. Review all context from intake and clarification
2. Generate exactly 3 implementation options (Minimal, Balanced, Comprehensive)
3. Offer PLAN mode as an alternative
4. Wait for the user to choose

Store the chosen plan for implementation.

---

## Phase 4 — Implement

Announce: `"## Phase 4 — Implement"`

Execute the chosen plan:

1. Work through the plan's file list methodically — create/modify files in a logical order (dependencies first, then dependents).
2. Follow existing codebase conventions discovered during intake (naming, patterns, structure).
3. **Pause on ambiguity** — if you encounter a decision not covered by the plan or clarification, stop and ask the user. Do not guess.
4. **Write tests** — As part of implementation, create tests that directly verify the acceptance criteria. Follow the testing patterns discovered during intake (framework, file locations, naming conventions).
5. **Run the test suite** — Execute the relevant tests using the project's test runner. If any tests fail, diagnose the issue (test bug vs. implementation bug), fix it, and re-run.
6. **Run the full suite** — If the project has a broader test suite, run it to ensure nothing was broken. Fix any regressions.
7. **Simplify (opt-in)** — If `--simplify` was provided, run `/simplify` on the changed files and apply any worthwhile suggestions.
8. After completing implementation, briefly summarize what was done: which files were created/modified and the key changes in each.

---

## Phase 5 — Verify

Announce: `"## Phase 5 — Verify"`

Invoke the `verify` skill using the `Skill` tool.

The verify skill will:
1. Retrieve acceptance criteria from the intake phase
2. Check each criterion against the implementation with concrete evidence (including test results from Phase 4)
3. Produce a pass/fail checklist
4. Offer to fix any failures

If there are failures, allow the verify skill to fix them. Re-verify until all criteria pass or the user accepts the remaining state.

---

## Phase 5.5 — Quality Gate

**If `--scorecard` was not provided:** Skip this phase entirely and proceed to Phase 6.

Announce: `"## Phase 5.5 — Quality Gate"`

Run a focused scorecard on the changed files to catch quality regressions introduced by this implementation.

### 1. Resolve Changed Files

Use `Bash` to get the list of uncommitted changed files:

```bash
git diff HEAD --name-only
```

Filter to only files that currently exist on disk. If the list is empty, announce: `"No uncommitted changes found for quality gate. Skipping."` and proceed to Phase 6.

### 2. Dispatch Quality Audits

Dispatch 3 parallel subagents using the `Agent` tool — one per category. All three are dispatched in the same response.

Each subagent prompt must contain:

```
You are auditing changed files for the **<Display Name>** quality category.

## Scoped File List
Audit ONLY the following changed files. Do NOT analyze files outside this list:
<list each file, one per line>

## Your Task
1. Use the `Skill` tool to invoke the `audit-<flag-value>` skill.
2. Follow the skill's instructions, restricting ALL sampling to the scoped file list above.
3. Skip any criteria that cannot be evaluated from the scoped files — note them as "not assessed (out of scope)."

## Required Output Format
Return ONLY a single JSON object:
{
  "category": "<flag-value>",
  "score": <integer 1-10>,
  "findings": [
    {
      "severity": "<CRITICAL|MAJOR|MINOR|SUGGESTION>",
      "description": "<what was found>",
      "location": "<file:line or file or 'repo-wide'>",
      "recommendation": "<actionable fix>"
    }
  ],
  "summary": "<one-line summary>"
}
Return ONLY the JSON. No other text.
```

Dispatch for these three categories:
- **Security** — skill: `audit-security`
- **Testability** — skill: `audit-testability`
- **Maintainability** — skill: `audit-maintainability`

### 3. Evaluate Results

Collect results from all three subagents.

**If all three subagents failed or returned non-JSON output**, this most likely means the scorecard plugin is not installed. Show a warning and continue:

> ⚠️ Quality gate skipped: the scorecard plugin does not appear to be installed. Install it with `/plugin install scorecard@kevnord-plugins`, then re-run with `--resume scorecard`.

Proceed to Phase 6.

**If some subagents succeeded and some failed**, use the successful results and note which categories could not be assessed.

Separate findings by severity across all categories.

Present a brief quality gate summary:

```
## Quality Gate Results

| Category       | Score | Top Finding                          |
|----------------|-------|--------------------------------------|
| Security       | N/10  | <most severe finding or "No issues"> |
| Testability    | N/10  | <most severe finding or "No issues"> |
| Maintainability| N/10  | <most severe finding or "No issues"> |
```

### 4. Handle Findings

**If there are CRITICAL findings:**
List each one and tell the user:
> Quality gate blocked on CRITICAL findings. Fix these before creating the PR, or type `skip` to proceed anyway.

Wait for the user's response. If they fix the issues, re-run the relevant subagent to confirm resolution. If they type `skip`, proceed to Phase 6.

**If there are MAJOR findings (no CRITICAL):**
List them and ask:
> These MAJOR findings were introduced by this change. Fix them now, or proceed to PR creation?

Wait for the user's response and act accordingly.

**If only MINOR/SUGGESTION findings or none:**
Announce: `"Quality gate passed. Proceeding to PR."` and continue to Phase 6.

---

## Phase 6 — PR

Announce: `"## Phase 6 — PR"`

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
- **Quality gate:** <passed / blocked (N CRITICAL fixed) / skipped (scorecard not installed) / not run>
- **PR:** <URL or "skipped">

### Files Changed
- `<path>` — <brief description of change>
- ...
```
