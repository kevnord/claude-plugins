---
description: Score your code across 10 quality dimensions and produce a weighted composite scorecard
argument-hint: "[--categories <list>] [--weight <cat>=<n>] [--min-score <n>] [--min-category-score <n>] [--standards-path <path>] [--standards-url <url>]"
---

# Scorecard

You are orchestrating a comprehensive repository health audit across up to 10 quality categories. Each category is evaluated by an independent subagent that invokes a specialized audit skill. Results are aggregated into a weighted composite score with an optional pass/fail quality gate. Follow these phases exactly.

---

## Phase 1: Parse Arguments & Repo Discovery

### 1.1 Parse Arguments

Parse `$ARGUMENTS` for the following optional flags:

- `--categories <comma-separated-list>` — restrict audit to specific categories (flag values). If omitted, all applicable categories are audited.
- `--weight <flag-value>=<percentage>` — override the default weight for a category. May appear multiple times (e.g., `--weight security=30 --weight performance=20`). Unspecified categories share the remaining weight equally.
- `--min-score <n>` — composite score must meet or exceed this value to PASS (1-10).
- `--min-category-score <n>` — no single category score may fall below this value to PASS (1-10).
- `--standards-path <path>` — path to a local directory containing custom standards files.
- `--standards-url <url>` — URL to a remote directory containing custom standards files.
- `--scope <value>` — narrow the audit to only changed files. Supported values:
  - `uncommitted` — all uncommitted changes (staged + unstaged) via `git diff HEAD --name-only`
  - `staged` — only staged changes via `git diff --cached --name-only`
  - `HEAD~N` — changes in the last N commits via `git diff HEAD~N..HEAD --name-only` (e.g., `HEAD~3`)
  - `<ref>..<ref>` — arbitrary git commit range via `git diff <ref>..<ref> --name-only` (e.g., `main..feature-branch`)

If no arguments are provided, run a full audit with equal weights, no quality gate threshold, and full repo scope.

### 1.2 Category Name Mapping

Reference this table throughout the audit. These are the 10 audit categories:

| Directory Name          | Display Name       | Flag Value        |
|-------------------------|--------------------|-------------------|
| `audit-simplicity`      | Simplicity         | `simplicity`      |
| `audit-reuse`           | Reuse              | `reuse`           |
| `audit-security`        | Security           | `security`        |
| `audit-performance`     | Performance        | `performance`     |
| `audit-ui-ux`           | UI/UX              | `ui-ux`           |
| `audit-testability`     | Testability        | `testability`     |
| `audit-maintainability` | Maintainability    | `maintainability` |
| `audit-observability`   | Observability      | `observability`   |
| `audit-devops`          | DevOps Readiness   | `devops`          |
| `audit-api-design`      | API Design         | `api-design`      |

### 1.3 Detect Tech Stack

Use `Glob` to search for build and project files at the repository root and one level deep:

- `build.gradle*` / `settings.gradle*` — Kotlin/Java (Gradle)
- `pom.xml` — Java (Maven)
- `package.json` — JavaScript/TypeScript (Node.js)
- `*.csproj` / `*.sln` — .NET / C#
- `go.mod` — Go
- `Cargo.toml` — Rust
- `requirements.txt` / `pyproject.toml` / `setup.py` / `Pipfile` — Python
- `Gemfile` — Ruby
- `mix.exs` — Elixir
- `composer.json` — PHP

Use `Read` to read each detected build file. Extract:
- Primary language(s) and version(s)
- Framework(s) (e.g., React, Angular, Micronaut, Spring, ASP.NET, Express, FastAPI)
- Key dependencies and their versions
- Build tooling (e.g., Webpack, Vite, Gradle, Maven, dotnet CLI)

Store the full detected stack information for inclusion in subagent prompts.

### 1.4 Detect Repo Type

Based on the detected stack and directory structure, classify the repo as one of:

- **frontend** — contains only UI/client-side code (e.g., React app, Angular app, static site)
- **backend** — contains only server-side code (e.g., REST API, gRPC service, worker)
- **fullstack** — contains both frontend and backend code in the same repo
- **library** — published as a package/module for consumption by other projects (check for publishing config in build files)
- **CLI tool** — command-line application (check for bin entries, CLI frameworks)
- **monorepo** — contains multiple independently deployable projects (check for workspaces config, multiple build files in subdirectories, tools like Nx/Lerna/Turborepo)

Signals to use:
- Presence of `src/main` + `src/test` without UI files suggests **backend**
- Presence of `src/components` or `src/pages` or `src/app` with a UI framework suggests **frontend**
- Both backend and frontend indicators together suggest **fullstack**
- A `bin` field in `package.json`, or a CLI framework dependency (e.g., `commander`, `click`, `cobra`) suggests **CLI tool**
- Workspace configurations (`workspaces` in `package.json`, `settings.gradle` with multiple `include`, Nx/Lerna/Turborepo config) suggest **monorepo**
- Publishing configuration (`publishConfig`, `maven-publish` plugin, `nuget` packaging) suggests **library**

### 1.5 Auto-Skip Categories

Apply automatic category skipping based on the detected repo type:

- **Skip `ui-ux`** if the repo type is `backend`, `library`, or `CLI tool` and no frontend framework or UI component files are detected.
- **Skip `api-design`** if the repo has no API surface: no controller/handler files, no route definitions, no OpenAPI/Swagger specs, no API framework detected.

**Override rule:** If `--categories` is provided and explicitly includes a category that would be auto-skipped, the explicit request overrides the auto-skip. For example, `--categories ui-ux` on a backend repo forces the UI/UX audit to run.

### 1.6 Resolve Scope

If `--scope` is provided:

1. Run the appropriate `git diff` command using the `Bash` tool to get the list of changed files:
   - `uncommitted`: `git diff HEAD --name-only`
   - `staged`: `git diff --cached --name-only`
   - `HEAD~N`: `git diff HEAD~N..HEAD --name-only`
   - `<ref>..<ref>`: `git diff <ref>..<ref> --name-only`
2. Filter the output to only include files that currently exist on disk (changed files may include deleted files — exclude those).
3. If the resulting file list is empty, report an error to the user and stop: "No changed files found for scope `<value>`. Nothing to audit."
4. Store the file list as the **scoped file list**. This list will be passed to every subagent so they restrict their sampling to only these files.

If `--scope` is not provided, the scoped file list is empty, meaning subagents audit the full repository.

### 1.7 Load Custom Standards

Load custom standards from up to three sources in this precedence order (highest precedence first):

#### Source A: Repo-local (`.scorecard/` directory in repo root)

1. Use `Glob` to check for `.scorecard/` at the repo root.
2. If it exists, use `Read` to load `.scorecard/config.md` if present.
3. Use `Glob` to find all `.scorecard/*.md` files. For each category file (e.g., `.scorecard/security.md`), use `Read` to load its contents. Tag all criteria from this source with `[repo-local]`.

#### Source B: Standards path (`--standards-path`)

1. If `--standards-path` is provided, use `Glob` to find all `*.md` files in the specified directory.
2. Use `Read` to load `config.md` if present.
3. For each category file, use `Read` to load its contents. Tag all criteria from this source with `[standards-path]`.

#### Source C: Standards URL (`--standards-url`)

1. If `--standards-url` is provided, use the `WebFetch` tool to fetch `config.md` from `<url>/config.md`. If the fetch fails (404 or other error), skip the config — do not fail the audit.
2. For each of the 10 category flag values (`simplicity`, `reuse`, `security`, `performance`, `ui-ux`, `testability`, `maintainability`, `observability`, `devops`, `api-design`), use `WebFetch` to fetch `<url>/<flag-value>.md`. If any individual fetch fails, skip that category file — do not fail the audit.
3. Fetch all remote files in a single batch of `WebFetch` calls (one call per file, but dispatch them together to minimize latency). Store all fetched content in memory for the duration of the audit. Do NOT re-fetch during later phases.
4. Tag all criteria from this source with `[standards-url]`.

#### Merging Rules

- **`config.md` settings** — merge from all sources. When the same setting appears in multiple sources, the highest-precedence source wins. Precedence order: repo-local > standards-path > standards-url.
- **Category criteria** — append criteria from all sources. Do NOT replace; each source's criteria are added to the evaluation list. Maintain the source tag on each criterion so findings can be attributed.
- **CLI flags always override `config.md`** — if `--weight`, `--min-score`, `--min-category-score`, or `--categories` are provided as CLI arguments, they take precedence over any values in any `config.md`.

Parse `config.md` for the following sections:
- `## Default Weights` — lines like `- security=25` set default category weights
- `## Skip Categories` — lines like `- ui-ux` add categories to the skip list (unless overridden by `--categories`)
- `## Default Thresholds` — lines like `- min-score: 7` and `- min-category-score: 5` set quality gate thresholds

### 1.8 Report Discovery Summary

Before proceeding, present a summary to the user:

```
Repository Discovery Summary
─────────────────────────────
Repo path:       <path>
Tech stack:      <language(s), framework(s), build tool(s)>
Repo type:       <frontend|backend|fullstack|library|CLI tool|monorepo>
Scope:           <full repo, or: "uncommitted changes (N files)" / "staged changes (N files)" / "HEAD~N (N files)" / "<ref>..<ref> (N files)">
Categories:      <list of categories that will be audited>
Skipped:         <list of auto-skipped categories and reason, or "none">
Standards loaded:
  - Repo-local (.scorecard/): <loaded / not found>
  - Standards path:             <loaded from <path> / not provided>
  - Standards URL:              <loaded from <url> / not provided>
Weights:         <default (equal) or custom breakdown>
Quality gate:    <min-score=N, min-category-score=N, or "no threshold set">
```

---

## Phase 2: Dispatch Category Audits

### 2.1 Determine Active Categories and Waves

From Phase 1, you have the final list of active categories (after applying `--categories` filter, auto-skip, and `config.md` skip rules).

Assign categories to waves:

- **Wave 1:** Security, Performance, Testability, Maintainability, Simplicity
- **Wave 2:** Reuse, UI/UX, Observability, DevOps Readiness, API Design

Only include categories that are in the active list. If the total number of active categories is 5 or fewer, use a single wave containing all of them.

### 2.2 Dispatch Wave 1

For each category in Wave 1, dispatch a subagent using the `Agent` tool. All subagents in a wave are dispatched in parallel (multiple `Agent` tool calls in the same response).

Each subagent prompt must contain the following (paste all content inline — do NOT pass references for the subagent to fetch):

```
You are auditing a repository for the **<Display Name>** quality category.

## Repository Context
- **Repo path:** <repo path>
- **Detected tech stack:** <language(s), framework(s), build tool(s), key dependencies>
- **Repo type:** <frontend|backend|fullstack|library|CLI tool|monorepo>
- **Audit scope:** <"full repo" or the --scope value provided>

## Scoped File List
<If a scoped file list was collected in Phase 1.6, list every file here, one per line. Example:>
This audit is scoped to the following changed files ONLY. Do NOT sample or analyze files outside this list:
- src/services/user-service.ts
- src/controllers/auth-controller.ts
- tests/services/user-service.test.ts
<If no scope was provided, state: "Full repository — sample broadly per the skill's sampling strategy.">

## Your Task
1. Use the `Skill` tool to invoke the `audit-<flag-value>` skill. This skill contains the full evaluation criteria, scoring rubric, and sampling strategy for this category.
2. After invoking the skill, follow its instructions to audit the repository. **If a scoped file list is provided above, restrict ALL sampling and analysis to only those files.** Skip any criteria that cannot be evaluated from the scoped files and note them as "not assessed (out of scope)."
3. Evaluate BOTH the built-in criteria from the skill AND the custom criteria listed below.

## Custom Criteria for This Category
<If custom criteria exist for this category from any standards source, list them here, each prefixed with its source tag. Example:>
- [repo-local] All services MUST use the internal auth middleware [CRITICAL if missing]
- [standards-path] Database migrations must use Flyway naming convention [MAJOR if violated]
- [standards-url] All public methods must have JSDoc comments [MINOR if missing]
<If no custom criteria exist for this category, state: "No custom criteria. Evaluate using built-in criteria only.">

## Required Output Format
You MUST return ONLY a single JSON object as your final output. No additional text, explanation, or markdown formatting around it. The JSON must conform to this exact schema:

{
  "category": "<flag-value>",
  "score": <integer 1-10>,
  "confidence": "<High|Medium|Low>",
  "findings": [
    {
      "severity": "<CRITICAL|MAJOR|MINOR|SUGGESTION>",
      "description": "<what was found>",
      "location": "<file-path:line-number or file-path or 'repo-wide'>",
      "recommendation": "<actionable fix>"
    }
  ],
  "top_recommendations": [
    "<most impactful recommendation>",
    "<second most impactful>",
    "<third most impactful>"
  ],
  "summary": "<one-line summary of this category's health>"
}

Scoring guidance:
- 9-10: No CRITICAL or MAJOR findings, 2 or fewer MINOR findings (Excellent)
- 7-8: No CRITICAL findings, 2 or fewer MAJOR findings (Good)
- 5-6: No CRITICAL findings, 5 or fewer MAJOR findings (Adequate)
- 3-4: 1 CRITICAL finding or more than 5 MAJOR findings (Poor)
- 1-2: Multiple CRITICAL findings (Critical)

Confidence guidance:
- High: Found and analyzed relevant artifacts in 3+ areas of the criteria checklist
- Medium: Found artifacts for 1-2 areas, inferred the rest
- Low: Minimal or no relevant artifacts found; score is largely inferred

Return ONLY the JSON object. No other text.
```

### 2.3 Wait for Wave 1 and Handle Failures

Wait for all Wave 1 subagents to complete. For each subagent result:

1. **Success** — the subagent returned valid JSON matching the output schema. Store the result.
2. **Failure** — the subagent failed, timed out, or returned non-JSON output. Record the category as SKIPPED with the following structure:
   ```json
   {
     "category": "<flag-value>",
     "score": null,
     "confidence": "None",
     "findings": [],
     "top_recommendations": [],
     "summary": "SKIPPED — <brief error description>",
     "error": "<full error details for the report>"
   }
   ```
   Do NOT retry the subagent. Do NOT fail the entire audit. Continue with the remaining categories.

To determine if a subagent returned valid JSON: check that the output contains a parseable JSON object with at minimum the `category`, `score`, `confidence`, and `findings` fields. If any required field is missing or the score is not an integer between 1 and 10, treat it as a failure.

### 2.4 Dispatch Wave 2

After all Wave 1 subagents have completed (or failed), dispatch Wave 2 using the same subagent prompt template and the same parallel dispatch approach. Apply the same failure handling.

### 2.5 Collect All Results

After Wave 2 completes, you should have results (success or SKIPPED) for every active category. Proceed to Phase 3.

---

## Phase 3: Aggregate & Score

### 3.1 Collect Results

Gather the JSON results from all subagents. Separate them into two lists:
- **Scored categories** — those with a valid numeric score (1-10)
- **Skipped categories** — those with `score: null` (failed/timed-out subagents or auto-skipped categories)

### 3.2 Compute Weights

1. **Start with equal weights.** Each of the 10 possible categories begins with a default weight of 10%.

2. **Apply `config.md` weight overrides.** If any merged `config.md` specified default weights, apply them. Categories not mentioned in `config.md` share the remaining weight equally.

3. **Apply CLI `--weight` overrides.** CLI flags always take final precedence. For each `--weight <category>=<percentage>` argument, set that category's weight to the specified value. Recalculate remaining unspecified categories to share the leftover weight equally.

4. **Redistribute skipped category weight.** For any category that is skipped (auto-skip, `config.md` skip, or subagent failure), take its weight and redistribute it evenly across all scored categories.

5. **Normalize to 100%.** After all adjustments, verify that the weights of all scored categories sum to 100%. If they do not (due to rounding), adjust the largest-weight category to absorb the difference.

### 3.3 Compute Composite Score

Calculate the weighted composite score:

```
composite = sum(category_score * category_weight) for all scored categories
```

Where `category_weight` is expressed as a decimal (e.g., 10% = 0.10). Round the composite to one decimal place.

### 3.4 Determine Verdict

If quality gate thresholds are set (from CLI flags or merged `config.md`):

- **Check `--min-score`:** If the composite score is >= the threshold, the composite check PASSES. If below, it FAILS.
- **Check `--min-category-score`:** For every scored category, if all scores are >= the threshold, the category check PASSES. If any single category score is below, it FAILS. Record which categories failed.
- **Overall verdict:**
  - **PASS** — both checks pass (or only the applicable check passes if only one threshold is set)
  - **FAIL** — either check fails. Record the specific reason(s) for failure.

If no thresholds are set, the verdict is omitted from the report.

### 3.5 Rank Findings

1. Collect all findings from all scored categories into a single list.
2. Sort by severity: CRITICAL first, then MAJOR, then MINOR, then SUGGESTION.
3. Within the same severity, sort by category weight (higher-weighted categories first), then by the category score (lower-scored categories first, as findings from weaker categories are more impactful).

### 3.6 Select Top 3 Recommendations

From all categories' `top_recommendations` arrays, select the 3 highest-impact recommendations. Prioritize:
1. Recommendations from categories with the lowest scores
2. Recommendations that address CRITICAL findings
3. Recommendations from categories with the highest weights

---

## Phase 4: Generate Report

Present the full audit report to the user using the following structure. Fill in all sections completely — do not leave placeholders or TODOs.

```
## Scorecard Report

**Repo:** <repo name/path>
**Stack:** <detected language(s), framework(s)>
**Type:** <repo type>
**Scope:** <"Full repo" or scope description, e.g., "Uncommitted changes (12 files)" or "HEAD~3 (8 files)">
**Date:** <current date>
**Composite Score: <score>/10** | **Verdict: <PASS|FAIL>** <only if thresholds were set>
**Standards:** <list sources loaded, or "Built-in criteria only">

---

### Category Scores

| Category          | Score  | Weight | Confidence | Top Finding                           |
|-------------------|--------|--------|------------|---------------------------------------|
| <for each scored category, one row with: Display Name, score/10, weight%, confidence level, most severe finding summary> |
| <for each skipped category: Display Name, SKIPPED, —, —, reason for skip> |

---

### Critical & Major Findings

<numbered list of all CRITICAL and MAJOR findings across all categories, sorted by severity then impact>
<each entry formatted as:>
<N>. [<SEVERITY>][<Display Name>] <description> — <location>
   <if the finding originated from a custom criterion, append the source tag: (Source: [repo-local|standards-path|standards-url])>

<if no CRITICAL or MAJOR findings:>
No critical or major findings detected.

---

### Top 3 Recommendations

1. **<recommendation>** — <which category, why it matters>
2. **<recommendation>** — <which category, why it matters>
3. **<recommendation>** — <which category, why it matters>

---

### Quality Gate Result

<only include this section if --min-score or --min-category-score was set>

**Composite threshold:** <min-score value> — <PASS or FAIL (actual: <composite>)>
**Category threshold:** <min-category-score value> — <PASS or FAIL>
<if category threshold failed, list each failing category:>
  - <Display Name>: <score>/10 (below minimum of <threshold>)

**Overall: <PASS|FAIL>**

---

### Detailed Category Reports

<for each scored category, in the order they appear in the Category Scores table:>

#### <Display Name> (<score>/10, <Confidence> confidence)

**Summary:** <category summary from subagent>

**Findings:**

| # | Severity   | Description                          | Location        | Recommendation                  |
|---|------------|--------------------------------------|-----------------|---------------------------------|
| <numbered list of all findings for this category> |

<if any findings originated from custom criteria, note the source tag in the Description column, e.g., "[repo-local] Missing auth middleware">

**Top Recommendations for <Display Name>:**
1. <recommendation 1>
2. <recommendation 2>
3. <recommendation 3>

---

<for each skipped category:>

#### <Display Name> (SKIPPED)

**Reason:** <why it was skipped — auto-skip due to repo type, config.md skip rule, subagent failure, etc.>
<if skipped due to subagent failure, include error details:>
**Error:** <error details from the subagent>
```

---

## Phase 5: Export Prioritized Fix List

After presenting the full report, ask the user:

> Would you like me to generate a prioritized fix list as a Markdown file?

If the user agrees:

1. Generate a file named `scorecard-fixes.md` in the repository root with the following structure:

```markdown
# Scorecard — Prioritized Fix List

**Repo:** <repo name/path>
**Date:** <current date>
**Composite Score:** <score>/10

## How to use this list

Work through items top to bottom. Each item is ordered by impact — fixing items higher on the list will improve the composite score the most. Check off items as you go.

---

## Critical Priority

<for each CRITICAL finding, ordered by category weight (highest first):>
- [ ] **[<Display Name>]** <description> — `<location>`
  - **Fix:** <recommendation>

## High Priority

<for each MAJOR finding, ordered by category weight (highest first), then by category score (lowest first):>
- [ ] **[<Display Name>]** <description> — `<location>`
  - **Fix:** <recommendation>

## Medium Priority

<for each MINOR finding, ordered the same way:>
- [ ] **[<Display Name>]** <description> — `<location>`
  - **Fix:** <recommendation>

## Suggestions

<for each SUGGESTION finding:>
- [ ] **[<Display Name>]** <description> — `<location>`
  - **Fix:** <recommendation>
```

2. Use the `Write` tool to save the file.
3. Tell the user the file path and that they can track progress by checking off items.
