# skim-colors

Colours Claude's replies in the terminal so they're easier to skim. Each reply is redrawn with colour cues from your theme; the reply itself is unchanged, and ctrl+o still shows it as written.

## What it highlights

| What | How | Example |
|------|-----|---------|
| Headings, and a bold lead-in at the start of a line | Claude's accent colour, bold | **Moved to Done:** |
| Ticket and PR identifiers | `suggestion` colour | KEV-1344, PR #224 |
| Inline code: paths, commands, flags | `permission` colour | `packing-station.scad` |
| Links | `suggestion` colour, underlined | |
| Figures with units | bold | 44 × 42 mm, 83 g, 260 layers |
| Warning phrases | `warning` colour | not committed, can't, failed, blocked |
| Confirmations | `success` colour | passed, verified |

List bullets are drawn as `•` in the accent colour.

Tables, code blocks, block quotes and rules are left to Claude Code's own Markdown renderer, as are collapsed summaries and every surface but the terminal.

## Install

```
/plugin install skim-colors@kevnord-plugins
```

It is a hooks module (`hooks/register.tsx`, a `ui.render` hook on `AssistantMessage`), so it has no commands: once installed, replies are coloured.

## Changing it

The colours are theme keys at the top of `hooks/register.tsx` (`LABEL`, `CODE`, `IDENT`, `LINK`, `WARN`, `GOOD`); the patterns are the `HIGHLIGHT` regular expression below them. After an edit, run `/reload-plugins`.

```sh
claude plugin validate plugins/skim-colors
claude plugin test plugins/skim-colors
```
