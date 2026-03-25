# Guided-Dev Artifact Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ADR and acceptance record generation to the guided-dev command so each workflow run persists two artifacts to disk.

**Architecture:** Single-file change to the command prompt (`guided-dev.md`). Artifact generation instructions are inlined at the end of Phase 3 and Phase 6. Phase 7 and Workflow Complete get minor additions to reference the artifacts.

**Spec:** `docs/superpowers/specs/2026-03-25-guided-dev-artifact-persistence-design.md`

**Important notes for implementing agents:**
- **Line number drift:** Each task modifies the same file. Line numbers in "Modify:" headers reference the *original* file before any changes. Always search for the **anchor text** quoted in each insertion instruction rather than relying on line numbers.
- **Resume/no-pr behavior:** Artifact generation is inlined within Phase 3 and Phase 6. If `--resume` skips past those phases, artifacts are inherently skipped — no guard clauses needed. If `--no-pr` is used, artifacts are still written since they happen before Phase 7. Do not add conditional logic for these cases.
- **`--skip-review` independence:** Skipping Phase 5 (review) does not affect Phase 6 (verify) or its acceptance record. They are independent phases.

---

### Task 1: Add ADR generation to Phase 3

**Files:**
- Modify: `plugins/guided-dev/commands/guided-dev.md` — Phase 3 (Design) section

- [ ] **Step 1: Add ADR generation instructions after the hard gate**

Find the line reading `Store the chosen plan for implementation.` in Phase 3. Insert the following content after that line, before the `---` separator that ends Phase 3:

````markdown

### Generate ADR

After the user selects an approach, generate an Architecture Decision Record:

1. **Determine sequence number:** Run `ls docs/adr/ 2>/dev/null | grep -E '^\d{4}-.*\.md$' | sort -r | head -1` to find the highest existing number. If the directory doesn't exist or is empty, start at `0001`. Otherwise increment by 1 and zero-pad to 4 digits.
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

Announce: `"ADR written to docs/adr/NNNN-<slug>.md"`
````

- [ ] **Step 2: Verify the edit**

Read `plugins/guided-dev/commands/guided-dev.md` and confirm:
- The ADR generation block appears after `Store the chosen plan for implementation.`
- The hard gate (`The user must select an approach before implementation begins.`) is still intact above it
- Phase 4 still starts cleanly after the `---` separator

- [ ] **Step 3: Commit**

```bash
git add plugins/guided-dev/commands/guided-dev.md
git commit -m "feat(guided-dev): add ADR generation to Phase 3"
```

---

### Task 2: Add acceptance record generation to Phase 6

**Files:**
- Modify: `plugins/guided-dev/commands/guided-dev.md` — Phase 6 (Verify) section

- [ ] **Step 1: Add acceptance record generation after verification resolves**

Find the line reading `Re-verify until all criteria pass or the user accepts the remaining state.` in Phase 6. Insert the following content after that line, before the `---` separator that ends Phase 6:

````markdown

### Generate Acceptance Record

After the verification loop fully resolves (all criteria pass, or the user accepts the remaining state):

1. **Determine sequence number:** Run `ls docs/acceptance/ 2>/dev/null | grep -E '^\d{4}-.*\.md$' | sort -r | head -1` to find the highest existing number. If the directory doesn't exist or is empty, start at `0001`. Otherwise increment by 1 and zero-pad to 4 digits.
2. **Reuse slug:** Use the same slug derived in Phase 3. If Phase 3 was skipped (e.g., `--resume implement`), derive the slug now from the task description using the same algorithm.
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

Announce: `"Acceptance record written to docs/acceptance/NNNN-<slug>.md"`
````

- [ ] **Step 2: Verify the edit**

Read `plugins/guided-dev/commands/guided-dev.md` and confirm:
- The acceptance record block appears after the re-verify instruction
- The conditional gate logic is still intact above it
- Phase 7 still starts cleanly after the `---` separator

- [ ] **Step 3: Commit**

```bash
git add plugins/guided-dev/commands/guided-dev.md
git commit -m "feat(guided-dev): add acceptance record generation to Phase 6"
```

---

### Task 3: Update Phase 7 PR description to include artifacts

**Files:**
- Modify: `plugins/guided-dev/commands/guided-dev.md` — Phase 7 (PR) section

- [ ] **Step 1: Add artifacts section to PR description**

Find the line reading `- Testing summary` in the Phase 7 PR description bullet list. Add after it:

```markdown
     - Artifacts generated (with file paths):
       - ADR: `docs/adr/NNNN-<slug>.md` (if generated this run)
       - Acceptance Record: `docs/acceptance/NNNN-<slug>.md` (if generated this run)
```

- [ ] **Step 2: Commit**

```bash
git add plugins/guided-dev/commands/guided-dev.md
git commit -m "feat(guided-dev): include artifacts in Phase 7 PR description"
```

---

### Task 4: Update Workflow Complete summary to include artifact paths

**Files:**
- Modify: `plugins/guided-dev/commands/guided-dev.md` — Workflow Complete section

- [ ] **Step 1: Add artifact lines to the summary template**

Find the line reading `- **PR:** <URL or "skipped">` in the Workflow Complete summary block. Add after it:

```markdown
- **ADR:** <path or "skipped (resumed past Phase 3)">
- **Acceptance record:** <path or "skipped (resumed past Phase 6)">
```

- [ ] **Step 2: Verify the complete file**

Read the full `plugins/guided-dev/commands/guided-dev.md` end-to-end and confirm:
- All four insertion points are correct
- No existing functionality was disrupted
- The flow reads naturally from Phase 3 -> 4 -> 5 -> 6 -> 7 -> Complete
- Markdown formatting is valid (no broken fences, headers, or lists)

- [ ] **Step 3: Commit**

```bash
git add plugins/guided-dev/commands/guided-dev.md
git commit -m "feat(guided-dev): add artifact paths to Workflow Complete summary"
```

---

### Task 5: Update README with artifact documentation

**Files:**
- Modify: `plugins/guided-dev/README.md`

- [ ] **Step 1: Add artifacts section to README**

Add a brief section documenting the two artifacts, where they're written, and when. Keep it concise — 5-8 lines.

- [ ] **Step 2: Commit**

```bash
git add plugins/guided-dev/README.md
git commit -m "docs(guided-dev): document artifact generation in README"
```
