---
description: Install, preview, or reconfigure the Claude Code status line
argument-hint: "[install | show | doctor | gallery | preset <name> | set KEY=VALUE | budget <amount>]"
---

# Status line

Use the `statusline` skill to handle this request.

`$ARGUMENTS` is the user's intent, in whatever form they typed it. Map it onto
the skill's CLI:

- empty, or "set it up" / "install" → `install`, then `doctor`
- "what is set" / "show" → `show`
- "blank" / "broken" / "wrong" → `doctor`
- a look-and-feel change ("blocks", "emoji", "make it look different") →
  **render the gallery first** and let the user pick from real output, per the
  skill's rules; never describe the variants in prose alone
- a budget figure → `budget <amount>`
- anything naming a config key → `set KEY=VALUE`

Follow the skill's guidance rather than improvising: it is the source of truth
for which command to run and how to present the result.
