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

After the user selects an architecture option from the competing blueprints:

1. Scan `docs/adr/` for existing files to determine next sequence number
2. Create `docs/adr/` if it doesn't exist
3. Generate ADR from:
   - **Context**: Task description from Phase 1 intake
   - **Options Considered**: Summaries from each code-architect agent (with their philosophy labels)
   - **Decision**: The user's chosen option with their rationale
   - **Consequences**: Trade-offs from the chosen blueprint
4. Write to `docs/adr/NNNN-<decision-title>.md`

**Phase 6 (Verify) — Write Acceptance Record**

After verification completes (all criteria checked):

1. Scan `docs/acceptance/` for existing files to determine next sequence number
2. Create `docs/acceptance/` if it doesn't exist
3. Generate acceptance record from:
   - **Task Description**: From Phase 1 intake
   - **Acceptance Criteria + Results**: Criteria from Phase 1, verification status and evidence from Phase 6
4. Write to `docs/acceptance/NNNN-<feature-name>.md`

**Phase 7 (PR) — Include artifacts**

The ADR and acceptance record are included in the PR alongside code changes. No separate commit needed.

### File Structure

```
project-root/
  docs/
    adr/
      0001-<decision-title>.md
      0002-<decision-title>.md
    acceptance/
      0001-<feature-name>.md
      0002-<feature-name>.md
```

Within the plugin:

```
plugins/guided-dev/
  templates/
    adr.md                  # ADR template with placeholders
    acceptance-record.md    # Acceptance record template with placeholders
  commands/
    guided-dev.md           # Updated phases 3, 6, 7
```

### ADR Template

```markdown
# NNNN. <Decision Title>

## Status
Accepted

## Date
YYYY-MM-DD

## Context
<Task description and why a design decision was needed>

## Options Considered

### Option 1: <Name> -- <Philosophy>
<Summary from code-architect agent output>

### Option 2: <Name> -- <Philosophy>
<Summary from code-architect agent output>

### Option 3: <Name> -- <Philosophy> (if applicable)
<Summary from code-architect agent output>

## Decision
<Chosen option with rationale from user selection>

## Consequences
<What becomes easier or harder, pulled from the chosen blueprint's trade-offs section>
```

### Acceptance Record Template

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

### Naming Conventions

- **Sequence numbers**: 4-digit zero-padded, auto-incremented by scanning existing files in the target directory. Starts at `0001`.
- **Slugs**: Kebab-case, derived from the decision title (ADR) or feature name (acceptance record). Max 50 characters.
- **Examples**: `0003-switch-to-event-driven-auth.md`, `0007-user-profile-search.md`

### Behavioral Details

- Directories are created lazily (on first write), not at plugin install
- If `--no-pr` is used, artifacts are still written to disk
- If `--resume` skips past Phase 3, no ADR is generated for that run
- If `--resume` skips past Phase 6, no acceptance record is generated for that run
- If all criteria PASS, acceptance record is written automatically
- If some criteria FAIL and user accepts the remaining state, acceptance record is still written (with FAIL statuses preserved)

## Files to Modify

1. **`plugins/guided-dev/commands/guided-dev.md`** — Add artifact generation instructions to Phase 3 (after architecture selection) and Phase 6 (after verification). Update Phase 7 to mention artifacts in PR.
2. **`plugins/guided-dev/templates/adr.md`** (new) — ADR template with placeholders
3. **`plugins/guided-dev/templates/acceptance-record.md`** (new) — Acceptance record template with placeholders

## Out of Scope

- Explore reports (Phase 2) — stale immediately, code is the source of truth
- Review findings (Phase 5) — issues are either fixed or belong in a ticket tracker
- Customizable output directories — follow convention, override not needed now
- Customizable templates — templates are in the plugin and can be forked if needed
