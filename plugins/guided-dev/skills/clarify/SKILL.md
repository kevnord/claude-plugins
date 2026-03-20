---
name: clarify
description: Ask targeted clarifying questions one at a time to resolve ambiguities and unstated assumptions. Use when gathering requirements, clarifying scope, or identifying gaps before planning.
---

# Clarify

## Purpose

Reviews all context gathered during intake and systematically identifies gaps, ambiguities, and unstated assumptions. Asks targeted questions one at a time, using multi-choice options where possible, to build a complete and unambiguous picture of the task before planning begins.

## Process

### 1. Analyze Context for Gaps

Review the intake summary and identify:

- **Scope boundaries** — What's included vs. excluded? Are there adjacent features that might be affected?
- **Edge cases** — What happens with empty inputs, large datasets, concurrent access, network failures?
- **Error handling** — How should errors be surfaced to the user? Should they be logged, retried, or silently handled?
- **Performance constraints** — Are there latency, throughput, or resource limits?
- **Compatibility** — Does this need to work with specific versions, browsers, or environments?
- **UX decisions** — How should the user interact with this? Are there loading states, confirmation dialogs, or feedback mechanisms?
- **Deployment** — Does this require migrations, feature flags, or phased rollout?
- **Testing expectations** — What level of test coverage is expected? Unit, integration, e2e?
- **Integration points** — Does this interact with external services, APIs, or databases?
- **Security implications** — Does this handle user data, authentication, or authorization?

Prioritize questions by impact — ask about things that would significantly change the implementation approach first.

### 2. Ask Questions One at a Time

**Critical rule: Ask exactly ONE question per message. Never batch multiple questions.**

Format each question with multi-choice options where possible, and always include your recommendation:

```
**Question 1 of up to N. Remaining topics: [topic1, topic2, ...]**

<Context for why this question matters>

<The question>

A) <Option A — brief description>
B) <Option B — brief description>
C) <Option C — brief description>
D) Other (please describe)

**My recommendation: <Option letter>** — <one-line rationale>
- *For:* <reasons this option is the best choice — e.g., aligns with existing patterns, simplest to maintain, best user experience>
- *Against:* <honest trade-offs or downsides of this recommendation — e.g., less flexible, adds complexity, slower performance>
```

When multi-choice doesn't fit (e.g., open-ended questions about business logic), ask a focused, specific question and still provide your recommended answer with reasons for and against it.

### 3. Track Progress

After each answer:

1. Acknowledge the answer briefly
2. State progress: `"Question N of up to M. Remaining topics: [...]"`
3. If the answer raises follow-up questions, add them to your list
4. If the answer eliminates planned questions, remove them

### 4. Respect the User's Time

- The user can say "that's enough", "let's move on", "skip", or similar at any time — immediately stop asking and proceed to the summary
- If you've asked 5+ questions and the remaining gaps are minor, offer: "I have a few more questions but none are critical. Want to continue or move on?"
- Never exceed the max question count (default 20, overridable via `--max-questions`)

### 5. Output Decisions Summary

When clarification is complete (all questions asked, user stopped early, or max reached), produce:

```
## Clarification Summary

### Decisions Made
1. **<Topic>:** <Decision> *(Question N)*
2. **<Topic>:** <Decision> *(Question N)*
3. ...

### Assumptions (not explicitly confirmed)
- <Assumption 1 — and why it's reasonable>
- <Assumption 2>

### Out of Scope (explicitly excluded)
- <Item 1>
- <Item 2>
```

This summary is appended to the intake context and passed to the planning phase.
