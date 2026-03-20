---
name: plan
description: Generate three implementation options at different complexity levels for the user to choose from. Use when creating an implementation plan, architecture plan, or presenting design options.
---

# Plan

## Purpose

Synthesizes all context from intake and clarification to generate exactly three implementation options at different complexity levels. Each option is concrete enough for the user to make an informed choice, with clear trade-offs and file-level detail.

## Process

### 1. Review All Context

Before generating options, review:

- The intake summary (task description, acceptance criteria, repo context, relevant files)
- The clarification summary (decisions, assumptions, exclusions)
- The actual codebase patterns (how similar features are implemented today)

### 2. Generate Three Options

Present exactly three options:

```
## Implementation Options

### Option A — Minimal
**Approach:** <1-2 sentence summary of the simplest approach that meets all acceptance criteria>

**Files to create/modify:**
- `<path>` — <what changes>
- `<path>` — <what changes>

**Complexity:** Low
**Estimated scope:** <e.g., "~50 lines changed across 2 files">

**Trade-offs:**
- (+) <advantage — e.g., fastest to implement, smallest diff>
- (+) <advantage>
- (-) <drawback — e.g., may need rework if requirements expand>
- (-) <drawback>

**Risks:**
- <risk, if any>

---

### Option B — Balanced (Recommended)
**Approach:** <1-2 sentence summary — good architecture and maintainability without over-engineering>

**Files to create/modify:**
- `<path>` — <what changes>
- `<path>` — <what changes>

**Complexity:** Medium
**Estimated scope:** <e.g., "~150 lines changed across 4 files">

**Trade-offs:**
- (+) <advantage — e.g., clean separation of concerns, easy to test>
- (+) <advantage>
- (-) <drawback — e.g., slightly more work upfront>

**Risks:**
- <risk, if any>

---

### Option C — Comprehensive
**Approach:** <1-2 sentence summary — most thorough, may include future-proofing or extensibility>

**Files to create/modify:**
- `<path>` — <what changes>
- `<path>` — <what changes>

**Complexity:** High
**Estimated scope:** <e.g., "~300 lines changed across 7 files, 1 new file">

**Trade-offs:**
- (+) <advantage — e.g., handles future requirements, more robust>
- (+) <advantage>
- (-) <drawback — e.g., larger diff, more to review, higher risk of scope creep>

**Risks:**
- <risk, if any>
```

### 3. Offer PLAN Mode Alternative

After presenting the three options, add:

> I can also use Claude Code's built-in **PLAN mode** to design the implementation interactively. Would you prefer that instead?
>
> **Choose:** A, B, C, or "use PLAN mode"

### 4. Wait for Selection

Do not proceed until the user selects an option. If the user asks for modifications to an option (e.g., "Option B but with the error handling from C"), accommodate and present the hybrid before confirming.

### Guidelines

- **Be concrete** — name actual files, functions, and patterns from the codebase. Don't use generic placeholders.
- **Stay grounded** — all three options must meet every acceptance criterion. The difference is in approach, not completeness.
- **Honest trade-offs** — don't make Option A sound bad to steer toward B. Each option is valid for different situations.
- **Match existing patterns** — the implementation should look like it was written by someone who already works on this codebase.
