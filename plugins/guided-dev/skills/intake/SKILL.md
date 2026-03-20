---
name: intake
description: Gather task requirements, explore the repository, and produce a structured context summary. Use when starting a new task or gathering requirements for implementation.
---

# Intake

## Purpose

Collects the task description, acceptance criteria, and supporting materials from the user, then explores the repository to build a structured context summary. This summary becomes the foundation for all subsequent workflow phases.

## Process

### 1. Collect Task Description

If an inline task description was provided (via `$ARGUMENTS` or the orchestrator), acknowledge it and confirm your understanding. Otherwise, ask the user:

> What problem are you trying to solve, or what feature do you want to build? Describe it in as much detail as you can.

Wait for the user's response before proceeding.

### 2. Collect Acceptance Criteria

Ask the user:

> What does "done" look like? List the acceptance criteria — the specific, verifiable conditions that must be true when this task is complete. If you're not sure, just say "suggest some" and I'll draft criteria based on your task description.

Wait for the user's response, then handle it based on what they provide:

**If the user provides clear criteria:** Help sharpen any vague ones into concrete, testable statements and proceed to the review step below.

**If the user provides vague criteria, says they're unsure, asks you to suggest, or provides no criteria:** Generate 3–7 acceptance criteria based on the task description. Derive them from:
- The core functionality described in the task
- Edge cases and error handling implied by the task
- Any integration points, API contracts, or UI behaviors mentioned
- Non-functional requirements if relevant (performance, security, accessibility)

Each criterion must be phrased as a verifiable statement (e.g., "The /users endpoint returns paginated results with a `next_cursor` field" rather than "pagination works").

**Review step (always):** Present the full list of acceptance criteria to the user in a numbered list and ask:

> Here are the acceptance criteria I'll use for this task:
>
> 1. \<criterion\>
> 2. \<criterion\>
> 3. ...
>
> Would you like to **add**, **remove**, or **edit** any of these? Reply with your changes, or say **"looks good"** to continue.

Incorporate any changes the user requests. If they make changes, present the updated list and ask again until they confirm. Only proceed once the user approves the final list.

### 3. Collect Supporting Materials

Ask the user:

> Do you have any supporting materials? Examples: file paths to reference, screenshots, JSON payloads, API specs, design docs, error messages, or links. Share anything that helps me understand the task.

If the user says no or provides materials, acknowledge and proceed.

### 4. Explore the Repository

Perform automated repo discovery:

1. **Directory structure** — Use `Glob` with patterns like `*`, `src/**`, `lib/**`, `app/**` to understand the top-level layout and key directories.
2. **Config files** — Use `Read` to examine key config files: `package.json`, `tsconfig.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Makefile`, `docker-compose.yml`, `.env.example`, or whatever build/config files exist at the root.
3. **Recent history** — Run `git log --oneline -20` to see recent commit messages and understand what's been worked on.
4. **Relevant code** — Based on the task description, use `Glob` and `Grep` to locate files and code patterns that are likely relevant. Read the most important ones.
5. **Conventions** — Look for:
   - Existing patterns (naming conventions, file organization, module structure)
   - Test patterns (test framework, test file locations, naming conventions)
   - Linting/formatting config (`.eslintrc`, `.prettierrc`, `rustfmt.toml`, etc.)
   - CI/CD config (`.github/workflows/`, `Jenkinsfile`, etc.)

### 5. Output Structured Summary

Produce a summary in this format:

```
## Intake Summary

### Task Description
<Clear, concise description of the task>

### Acceptance Criteria
1. <Criterion 1 — concrete and verifiable>
2. <Criterion 2>
3. ...

### Supporting Materials
- <List of files, screenshots, specs provided, or "None provided">

### Repository Context
- **Tech stack:** <language(s), framework(s), build tool(s)>
- **Project type:** <web app, API, library, CLI, etc.>
- **Key conventions:** <naming, structure, patterns observed>
- **Test setup:** <framework, location, patterns>
- **CI/CD:** <what's configured>

### Relevant Files
- `<path>` — <why it's relevant>
- `<path>` — <why it's relevant>
- ...

### Recent Activity
<Brief summary of recent commits relevant to this task>
```

This summary is passed to subsequent phases. Make it thorough — the quality of the plan depends on the quality of the intake.
