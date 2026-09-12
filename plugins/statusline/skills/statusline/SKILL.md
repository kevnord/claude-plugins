---
name: statusline
description: Install, preview, and reconfigure the Claude Code status line — model and effort, context %, the 5-hour and weekly usage windows (or a monthly budget meter), git branch state, the Jira key and status read off the branch, PR review exceptions, and plugin-drift alerts. Renders real examples before you choose. Use for "set up my statusline", "change the statusline layout", "switch to blocks or thin rules", "use emoji or minimal icons", "set my monthly Claude budget", "my statusline is blank or wrong", "show the Jira ticket in my statusline", "backfill month spend", or tuning BARS, ICONS, SEP, SHOW_*, JIRA_SITE, WATCH_PLUGIN, MONTHLY_LIMIT_USD in ~/.claude/statusline.conf.
---

# Status line

A two-to-three-line terminal readout driven by `~/.claude/statusline.sh`. One
`git status` spawn, one JSON parse, nothing over the network — about 70ms per
redraw.

```
payments-api ⎇ feature-PROJ-142-retry-backoff │ PROJ-142 In Progress │ opus-5 high
ctx ━━━━━━ 38% │ 5h 24% 2h30m   wk 47% 5d18h → 118%
PR #412 changes requested │ acme plugin 2 behind
```

Line one is repo, branch, the Jira key/PR found on it, and the model
answering. Line two is what you have spent, always. Line three appears only
when something is actionable — a requested change, a plugin behind its
marketplace — and is otherwise absent, not blank.

An earlier version carried a build-run segment behind `SHOW_IMPL`. It is gone.
A config still carrying `SHOW_IMPL` or an `IMPL_*` key is harmless; `SL install`
strips it, and the old `IL_PLUGIN` spelling is migrated to `WATCH_PLUGIN`.

Everything is driven by one CLI. `SL` below stands for:

```bash
python3 $CLAUDE_PLUGIN_ROOT/skills/statusline/scripts/slconf.py
```

## Always show examples before changing a choice

When the user is picking a gauge style or glyph set — including vague asks
like "make it look different" — **render the options first**, then ask.
Never describe the variants in prose alone; the whole point is that they are
visual.

```bash
SL gallery --dimension bars   # rule | blocks
SL gallery --dimension icons  # emoji | minimal
SL gallery --dimension sep    # bar | dot | space
SL gallery                    # every dimension
```

Each variant prints as a real render, marked `(current)` where it matches the
live config, with its column widths and the exact command to adopt it. Add
`--scenario alert|enterprise|load|nofh` to see it with a change requested, on an
Enterprise seat, under heavy usage, or before the 5-hour window has reported.

Paste the renders into your reply so the user sees them, then offer the choice
with `AskUserQuestion`. Terminal colour and emoji survive into the transcript,
so quote the output rather than re-typing it.

## Workflow

1. **First-time setup** — `SL install`. Copies the runtime to
   `~/.claude/statusline.sh`, seeds `~/.claude/statusline.conf`, points
   `settings.json` at it (backing the file up first), then runs the checks. It is
   idempotent: re-run it to upgrade the runtime, and existing config values are
   preserved unless `--force`. Then `SL doctor` to see which remote segments
   (Jira, plugin drift) are live, and `SL backfill` on an Enterprise seat.
2. **See what is set** — `SL show`. Prints every key, its value, whether that
   came from the config or a default, and the month-to-date ledger if a budget
   is active.
3. **Show the options** — `SL gallery …` as above.
4. **Apply** — `SL set KEY=VALUE …`, or `SL budget <amount>` for the budget. Values are validated before writing, so a
   typo cannot break the status line; the new state is previewed automatically.
   `SL unset KEY …` returns keys to their defaults.
5. **Confirm** — the next redraw picks the change up with no restart. If
   something looks wrong, `SL doctor`.
6. **Presets** — `SL preset default` (the full bundle) or `SL preset quiet`
   (keeps Jira and PR, turns plugin-drift off). Individual `SHOW_*` keys tune
   from there.

## Options

| Key | Values | Default | Effect |
|---|---|---|---|
| `BARS` | `rule` `blocks` | `blocks` | Thin `━` rule or solid `▓░` blocks, for every meter |
| `RULE_W` | 4–40 | `10` | Rule cells when `BARS=rule` |
| `BAR_WIDTH` | 3–20 | `6` | Block cells when `BARS=blocks` |
| `CTX_BAR_W` | 0–12 | `6` | Cells in the inline context gauge (`0` drops it) |
| `ICONS` | `emoji` `minimal` | `emoji` | 🌿🌳⏳📅 or `⎇ ⧉ 5h wk` |
| `LINKS` | `on` `off` | `on` | OSC 8 hyperlinks on the path and PR |
| `MONTHLY_LIMIT_USD` | money | unset | Your budget; enables the Enterprise-seat month meter |
| `WORKDAYS` | `mon-fri` `all` | `mon-fri` | Days the budget is spread across |
| `STEPS` | `yellow,orange,red` | `50,75,90` | Colour steps for the usage windows |
| `CTX_STEPS` | `yellow,orange,red` | follows `STEPS` | Colour steps for the context meter alone |
| `SHOW_WK_PACE` | `on` `off` | `on` | Weekly burn-rate projection chip |
| `HILITE_MODEL` | `on` `off` | `on` | Mark the model by tier: a filled chip, grey/green/amber/red for Haiku/Sonnet/Opus/Fable |
| `WK_PACE_STEPS` | `under,over,hot` | `50,100,150` | Steps for that chip, as % of the weekly window |
| `SL_PARSER` | `jq` `node` | auto | Force a JSON parser instead of detecting one |
| `SEP` | `bar` `dot` `space` | `bar` | Segment separator |
| `SEAT` | `auto` `team` `enterprise` | `auto` | Which usage tail to show |
| `SHOW_JIRA` `SHOW_PR` `SHOW_DRIFT` | `on` `off` | `on` | Each exception segment |
| `JIRA_SITE` | URL | unset | Your Jira site; without it the key shows but does not link |
| `WATCH_PLUGIN` | `plugin@marketplace` | unset | Plugin watched for drift; silent until set |

## Layout

`SL preset default` (or a fresh `SL install`) gives a layout built around one rule:
**line one is repo and branch and the ticket and the model answering; line
two is context and what you have spent, always; line three is only what needs
you.**

Line one: repo (plus `⧉ <name>` in a linked worktree), branch (green only
when clean), the Jira key found anywhere in the branch name with its status,
the PR's quiet status chip, and — last on the row — the model id with the
effort level spelled out (`low medium high xhigh max`). The branch is
introduced by the glyph set's branch mark (`⎇`, `🌿` under `ICONS=emoji`)
rather than the ordinary separator. The model is marked by tier so a mismatched
session stands out: every known tier wears a filled chip — Haiku grey, Sonnet
green, Opus amber, Fable red — and anything unrecognised stays plain.
`HILITE_MODEL=off` turns this off.

Line two: `agent <name>` when the session is a named agent, context % behind a
six-cell gauge, and the usage tail. The gauge takes its glyphs from `BARS`
and steps through `CTX_STEPS` (`yellow,red,chip`): green below the first value,
yellow to the second, red text to the third, then a filled red chip (dark ink,
so it still reads) past it — the context window is the one meter where a plain
red figure isn't escalation enough. `CTX_BAR_W=0` drops the gauge and leaves the
bare percentage.

Line three appears only when a segment has something actionable, in this fixed
order: PR, plugin drift. Each renders nothing when its state is good or its
data source is absent, so the line count is decided by the state, never by a
setting.

**Usage never hides.** `SEAT=auto` reads the seat from `~/.claude.json`:

| Seat | Tail | Source |
|---|---|---|
| Team (and Max/Pro) | `5h 80% 45m   wk 94% 3d16h → 142%` | the payload's rate-limit windows |
| Enterprise | `mo ━━━━━━━━  15% of $750 → $825` (month to date, cap, projected month-end by working days) | the local ledger; `MONTHLY_LIMIT_USD` defaults to 750 for this seat |

The Team tail's `→ 118%` is a burn-rate projection: where the weekly window
lands by its reset if you keep spending at the rate you have so far. It is paced
over **working days only** — weekends are excluded, so a quiet Saturday does not
flatter the figure. Any 7-day window covers each weekday exactly once, so the
window is always five working days however it happens to be aligned; the chip
divides usage so far by the working time already elapsed and extrapolates.

It shows only when the projection is worth acting on, and stays off the line in
the on-track band between:

| Projection | Renders | Meaning |
|---|---|---|
| ≤ `under` (50%) | green `→ 37%` | pacing well below the week — headroom to spend |
| 51–100% | nothing | on track |
| > `over` (100%) | amber `→ 118%` | on pace to exhaust the week before it resets |
| ≥ `hot` (150%), or week already red | red `→ 212%` | badly over |

Set `WORKDAYS=all` to pace it over calendar days instead, `SHOW_WK_PACE=off` to
drop it, or `WK_PACE_STEPS` to move the bands. The chip is suppressed for the
first six working hours of a window, where too little time has elapsed for the
extrapolation to mean anything.

**A mid-window reset** — Anthropic occasionally zeroes a Team seat's usage
part-way through the window, same reset time, a few times a year — is detected
from a drop in the raw percentage, and the projection re-anchors to the moment
of the drop instead of assuming a full nominal window, so it reflects the real
burn rate rather than reading falsely calm. See
[references/options.md](references/options.md) for the detection details and
its state file.

### Budget (Enterprise seats)

The month meter is Enterprise-only — a Team seat has no monthly quota the
harness reports against, so `MONTHLY_LIMIT_USD` there is tracked in the local
ledger but not shown. On an Enterprise seat it defaults to `$750` the moment
`SEAT` resolves to `enterprise`, or set your own:

```bash
SL budget 750           # exact monthly figure
SL budget 1250.50       # cents are kept
SL budget '$1,250'      # a $ and thousands separators are accepted
SL budget --daily 50    # derive the month from a daily rate x working days
SL budget               # show the current budget and its breakdown
SL budget --off         # turn it off
SL budget 750 --workdays all   # spread over 7 days instead of Mon-Fri
```

If the user has no figure in mind, do not invent one: offer to work out what
they have actually been spending first, then let them choose from real data.

**Two caveats to state when enabling it:**

1. **The ledger counts forward from now.** `~/.claude/.statusline-ledger`
   accumulates each session's reported cost from the moment it is enabled; it
   cannot backfill earlier spend, so the month meter reads low for the first
   few days — run `SL backfill` on an Enterprise seat to seed it from local
   transcripts instead.
2. **The dollars are API-equivalent value, not billing.** Nothing is charged
   at that rate and nothing is enforced — the budget is a self-imposed pacing
   target, not a spend cap.

### Remote segments

**Where the remote segments get their data.** The renderer never touches the
network. Each remote segment reads a cache file under `~/.claude/.statusline-cache`
and, when it is stale, spawns `~/.claude/statusline-refresh.py` detached and
keeps showing the old value. A source that is unavailable writes an empty entry
and the segment stays silent.

| Segment | Needs | Refresh |
|---|---|---|
| Jira status | `JIRA_SITE`, plus `JIRA_EMAIL` + `JIRA_API_TOKEN` (or the `ATLASSIAN_*` pair) in the environment | 5 min; with `JIRA_SITE` but no credentials the key still shows and links, just without a status |
| Plugin drift | `WATCH_PLUGIN`, plus `gh` for a GitHub marketplace or the local checkout for a directory one | daily |
| PR | nothing extra; the harness reports the branch PR's review state | live |

`SL doctor` lists which of these are active on this machine and what each
inactive one is missing.

## If something is wrong

`SL doctor` checks the dependencies, that the runtime is installed and
executable, that `settings.json` is wired, that every config value is valid,
and that the script actually renders.

**Dependencies are `git` plus either `jq` or `node`.** `jq` is preferred at
about 11ms; `node` is the fallback at about 51ms, which takes a redraw from
~70ms to ~124ms. Detection is automatic; `SL_PARSER=jq|node` forces one. With
neither installed the line does not go blank — it shows `needs jq or node`.

A blank status line is almost always an unwired `settings.json`, which
`SL install` fixes.

**On a brand-new or just-cleared session** there is no `rate_limits` block and
the context window is zero-sized, so the meters read `-- new session` and
`-- not reported yet` until the first API response. That is expected, not a
fault; the windows fill in on the first reply.

`SL uninstall` removes the `statusLine` key and leaves the files in place.

Field-by-field data provenance, the pacing arithmetic worked through, the git
state glyphs, and terminal-support caveats are in
[references/options.md](references/options.md).
