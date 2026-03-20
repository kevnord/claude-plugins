---
name: audit-ui-ux
description: Audit a repository for UI/UX quality and produce a scored assessment. Use when evaluating accessibility, responsive design, component consistency, or frontend user experience.
---

# Audit: UI/UX

## Purpose

Evaluates the user experience quality of frontend code. Checks accessibility (WCAG 2.1 AA), responsive design, error states, loading states, component consistency, form validation, and internationalization readiness. Skipped automatically for repos with no frontend code. A high score means the UI is accessible, responsive, and user-friendly; a low score means usability or accessibility gaps.

## Evaluation Criteria

### Accessibility (WCAG 2.1 AA)
- **What to look for:** Semantic HTML, ARIA attributes, color contrast, keyboard navigation
- **How to assess:** Check for semantic elements, ARIA attrs, alt text, and form labels. Grep for `aria-`, `role=`, `alt=`, `label`.
  - Good: Semantic elements used throughout, all images have alt text, all inputs have labels, keyboard navigation supported
  - Bad: Divs used for everything, missing alt text, unlabeled inputs, no focus management
- **Severity:** CRITICAL if no accessibility at all; MAJOR per specific violation found

### Responsive Design
- **What to look for:** CSS media queries, flexible layouts, viewport meta tag
- **How to assess:** Look for CSS media queries, flexbox/grid usage, and viewport meta tag.
  - Good: Mobile-first approach, flexible grid layouts, breakpoints for common screen sizes
  - Bad: Fixed-width layouts, no media queries, content clipped on small screens
- **Severity:** MAJOR if none present; MINOR if partial coverage

### Error States
- **What to look for:** User-facing error handling, validation messages, API error display
- **How to assess:** Check for error boundaries, inline validation messages, and meaningful feedback on failure.
  - Good: Helpful error messages, graceful degradation, clear recovery paths
  - Bad: Blank screens on failure, raw error codes shown, silent failures
- **Severity:** MAJOR if none present; MINOR if inconsistent or incomplete

### Loading States
- **What to look for:** Skeleton screens, spinners, progress indicators during async operations
- **How to assess:** Look for loading indicators shown while data fetches or actions are in progress.
  - Good: Skeleton screens or spinners displayed during all async operations
  - Bad: No feedback while loading, UI freezes without indication
- **Severity:** MINOR if inconsistent; SUGGESTION if present but could improve

### Component Consistency
- **What to look for:** Reusable component library, consistent UI patterns across pages
- **How to assess:** Check for a shared component library and consistent usage of patterns across the codebase.
  - Good: Shared component library used throughout, consistent styling and interaction patterns
  - Bad: UI elements reinvented per page, inconsistent styling, duplicated components
- **Severity:** MAJOR if no shared components; MINOR if partially shared

### Form Validation
- **What to look for:** Client-side validation, required field indicators, inline error messages
- **How to assess:** Check forms for real-time validation, required indicators, and descriptive error messages.
  - Good: Real-time validation with clear inline error messages, required fields marked
  - Bad: Validation only on submit, generic error messages, no required indicators
- **Severity:** MINOR per form with issues; MAJOR if no client-side validation anywhere

### Internationalization Readiness
- **What to look for:** Hardcoded user-facing strings, presence of i18n libraries or translation files
- **How to assess:** Grep for hardcoded English strings in JSX/templates. Look for i18n libraries (react-intl, i18next) or translation files.
  - Good: All user-facing strings extracted to translation files, i18n library in use
  - Bad: Hardcoded English strings throughout, no i18n infrastructure
- **Severity:** MINOR if hardcoded strings found; SUGGESTION if mostly translated but some gaps remain

## Scoring Rubric

Uses the global finding-count thresholds as defaults:
- 9-10: No CRITICAL or MAJOR findings, at most 2 MINOR
- 7-8: No CRITICAL, at most 2 MAJOR
- 5-6: No CRITICAL, at most 5 MAJOR
- 3-4: 1 CRITICAL or more than 5 MAJOR
- 1-2: Multiple CRITICAL findings

Total absence of accessibility is automatically scored as CRITICAL regardless of other findings.

## Sampling Strategy

**Scoped audit:** If a scoped file list is provided in the subagent prompt, restrict ALL sampling and analysis to only those files. Skip criteria that cannot be evaluated from the scoped files and note them as "not assessed (out of scope)."

1. Glob for component files (`.tsx`, `.jsx`, `.vue`, `.svelte`, `.cshtml`) to confirm frontend code exists; skip the audit if none are found
2. Deep-read up to 20 component files sampled across directories
3. Grep for accessibility markers (`aria-`, `role=`, `alt=`, `label`) and hardcoded user-facing strings
4. Set confidence:
   - **High**: Analyzed 20+ component files covering multiple directories and feature areas
   - **Medium**: Analyzed 10-19 files or coverage limited to a subset of the frontend
   - **Low**: Analyzed fewer than 10 files or the frontend is minimal

## References (future)

This skill supports future tech-specific criteria via the `references/` directory. At v2, matching `references/<stack>.md` files will be loaded automatically to add framework-specific UX checks.

## Output Schema

Return results as structured JSON:

```json
{
  "category": "ui-ux",
  "score": 6,
  "confidence": "High",
  "findings": [
    {
      "severity": "MAJOR",
      "description": "No alt text found on any img elements across 14 components reviewed",
      "location": "src/components/",
      "recommendation": "Add descriptive alt text to all images; use alt=\"\" for decorative images"
    }
  ],
  "top_recommendations": [
    "Add alt text to all images and ensure every form input has an associated label",
    "Introduce loading skeletons for the dashboard and search results pages",
    "Extract hardcoded English strings into translation files and integrate an i18n library"
  ],
  "summary": "Moderate UI/UX quality -- component library is consistent but missing alt text across the board, no loading states on async routes, and all user-facing strings are hardcoded in English"
}
```
