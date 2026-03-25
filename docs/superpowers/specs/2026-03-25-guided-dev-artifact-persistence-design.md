# Guided-Dev Artifact Persistence

## Summary

Add automatic generation of two persistent artifacts to the guided-dev workflow: an Architecture Decision Record (ADR) written after Phase 3 (Design), and an Acceptance Record written after Phase 6 (Verify). Both are optional-by-default in the sense that the plugin ships the capability, but artifacts are always generated when the workflow runs. No user configuration required.

## Motivation

The guided-dev workflow produces valuable intermediate outputs (competing architecture blueprints, acceptance criteria, verification evidence) that currently exist only in conversation context. Two of these have lasting value beyond the session:

- **"Why was it built this way?"** — answered by the ADR
- **"What was it supposed to do, and did it?"** — answered by the acceptance record

Everything else (explore reports, review findings) either goes stale immediately or belongs in a ticket tracker.

## Design

### Integration Points

**Phase 3 (Design) — Write ADR**

After the user selects an architecture option from the competing blueprints (the existing hard gate):

1. Scan `docs/adr/` for existing files to determine next sequence number (see Sequence Number Algorithm below)
2. Create `docs/adr/` if it doesn't exist
3. Generate ADR from:
   - **Context**: Task description from Phase 1 intake
   - **Options Considered**: Summaries from each code-architect agent. The orchestrator (command file) assigns philosophy labels at dispatch time ("Minimal changes", "Clean architecture", "Pragmatic balance") — the agents themselves do not output these labels. The Phase 3 instructions must carry the dispatch-time labels through to the ADR generation step.
   - **Decision**: The user's chosen option with their rationale
   - **Consequences**: Trade-offs from the chosen blueprint
4. Write to `docs/adr/NNNN-<slug>.md`

The ADR is written silently after the user's architecture selection — no additional approval gate. The user already approved the decision at the Phase 3 hard gate, and the ADR simply records that decision. The user can review the file in the PR.

**Phase 6 (Verify) — Write Acceptance Record**

After the verification loop fully resolves (all criteria pass, or the user accepts the remaining state after re-verification cycles):

1. Scan `docs/acceptance/` for existing files to determine next sequence number
2. Create `docs/acceptance/` if it doesn't exist
3. Generate acceptance record from:
   - **Task Description**: From Phase 1 intake
   - **Acceptance Criteria + Results**: The *final* verification state after all re-verify cycles — not the first pass. If fixes were applied and re-verified, the record reflects the post-fix status.
4. Write to `docs/acceptance/NNNN-<slug>.md`

**Phase 7 (PR) — Include artifacts**

The ADR and acceptance record are included in the PR alongside code changes. No separate commit needed. The PR description should explicitly call out the artifacts:

```
## Artifacts
- ADR: `docs/adr/NNNN-<slug>.md`
- Acceptance Record: `docs/acceptance/NNNN-<slug>.md`
```

**Workflow Complete summary** — Add artifact file paths to the structured summary output so the user knows where the files landed.

### File Structure

```
project-root/
  docs/
    adr/
      0001-<slug>.md
      0002-<slug>.md
    acceptance/
      0001-<slug>.md
      0002-<slug>.md
```

Within the plugin — no new files. Templates are inlined directly into the command file's Phase 3 and Phase 6 instructions, consistent with how the plugin currently works (all instructions are self-contained in the command and skill markdown files).

### ADR Format

```markdown
# NNNN. <Decision Title>

## Status
Accepted

## Date
YYYY-MM-DD

## Context
<Task description and why a design decision was needed>

## Options Considered

### Option 1: <Name> — <Philosophy>
<Summary from code-architect agent output>

### Option 2: <Name> — <Philosophy>
<Summary from code-architect agent output>

### Option 3: <Name> — <Philosophy> (if applicable)
<Summary from code-architect agent output>

## Decision
<Chosen option with rationale from user selection>

## Consequences
<What becomes easier or harder, pulled from the chosen blueprint's trade-offs section>
```

### Acceptance Record Format

```markdown
# <Feature Name>

## Date
YYYY-MM-DD

## Task Description
<From Phase 1 intake output>

## Acceptance Criteria

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | <criterion text> | PASS/FAIL | <file:line, test output, or config reference> |
```

### Sequence Number Algorithm

To determine the next sequence number for a directory:

1. List files in the target directory matching the pattern `^\d{4}-.*\.md$`
2. Extract the 4-digit numeric prefix from each matching filename
3. Take the maximum value found (or 0 if no matches)
4. Increment by 1 and zero-pad to 4 digits

Non-matching files (e.g., `README.md`, `template.md`) are ignored. Sequence numbers are per-branch; conflicts from concurrent runs on different branches are resolved at merge time (same as any file conflict).

### Slug Derivation

Slugs are derived from the task description (Phase 1 intake):

1. Lowercase the task description
2. Replace non-alphanumeric characters with hyphens
3. Collapse consecutive hyphens into one
4. Trim to 50 characters
5. Trim trailing hyphens

Both the ADR and acceptance record for the same feature use the same slug (derived from the same task description).

**Examples**: `add-user-profile-search`, `switch-to-event-driven-auth`, `fix-pagination-in-api-users`

### Behavioral Details

- Directories are created lazily (on first write), not at plugin install
- If `--no-pr` is used, artifacts are still written to disk
- If `--resume` skips past Phase 3, no ADR is generated for that run
- If `--resume` skips past Phase 6, no acceptance record is generated for that run
- If `--resume design` is used, the ADR is generated but the "Context" section may have less detail since it is reconstructed from git history rather than a full intake. This is acceptable.
- If all criteria PASS, acceptance record is written automatically
- If some criteria FAIL and user accepts the remaining state, acceptance record is still written (with FAIL statuses preserved)
- `--skip-review` (Phase 5) does not affect acceptance record generation (Phase 6) — they are independent phases

## Files to Modify

1. **`plugins/guided-dev/commands/guided-dev.md`** — Add artifact generation instructions to Phase 3 (after architecture selection gate), Phase 6 (after verification loop resolves), Phase 7 (artifacts in PR description), and Workflow Complete (artifact paths in summary).

No new files needed. Templates are inlined in the command instructions.

## Out of Scope

- Explore reports (Phase 2) — stale immediately, code is the source of truth
- Review findings (Phase 5) — issues are either fixed or belong in a ticket tracker
- Customizable output directories — follow convention, override not needed now
- Customizable templates — formats are inlined and can be forked if someone forks the plugin
- Separate template files — not needed given the plugin's self-contained instruction architecture
