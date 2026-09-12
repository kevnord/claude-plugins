# Status line reference

Detail behind [SKILL.md](../SKILL.md): where each field comes from, how pacing is
computed, what the git glyphs mean, and the terminal caveats.

## Where the data comes from

Claude Code pipes a JSON payload to the status-line command on stdin. Everything
except git state is already in it — no extra processes.

| Segment | Source | Notes |
|---|---|---|
| Folder | `workspace.current_dir` | Just the folder you are in, hyperlinked to it |
| Branch | `git status --branch` | During a rebase, the branch being rebased — not `detached at abc1234` |
| Dirty state | same git call | `!conflicts` `+staged` `~unstaged` `?untracked`, conflicts first |
| Operation in flight | files in the git dir | `REBASE n/m`, `AM`, `MERGE`, `CHERRY-PICK`, `REVERT`, `BISECT` |
| Ahead / behind | same git call | vs upstream; `⊘` when the branch has none |
| Worktree | `worktree.name`, else the `.git` file | Only in a linked worktree, never the main one |
| Context % | `context_window.used_percentage` | Behind an inline gauge sized by `CTX_BAR_W` |
| 5-hour window | `rate_limits.five_hour` | `used_percentage` + `resets_at` as a countdown |
| Weekly window | `rate_limits.seven_day` | `used_percentage` + `resets_at` as a countdown |
| Month, projection | local ledger ÷ `MONTHLY_LIMIT_USD` | No monthly window exists; Enterprise-seat only |
| Model id | `model.id` | Shown with the `claude-` prefix stripped; every known tier wears a filled chip — Haiku grey, Sonnet green, Opus amber, Fable red — and anything unrecognised stays plain (`HILITE_MODEL=off` for plain) |
| Model, effort | `model.display_name`, `effort.level` | Effort spelled out (`low medium high xhigh max`); plus `⚡` for fast mode |
| Subagent | `agent.name` | Opens line two, ahead of the context meter, when a subagent is active |
| Jira key | `[A-Z][A-Z0-9]{1,9}-[0-9]+` in the branch | Linked to `JIRA_SITE/browse/KEY` when `JIRA_SITE` is set, plain otherwise; status from the cache |
| PR | `pr.number`, `.url`, `.review_state` | Hyperlinked to the pull request |
| Seat / plan | `~/.claude.json` `oauthAccount` | Not in the payload; read separately and cached 12h |

Two things the harness does **not** provide, at all:

- **A monthly usage window.** Only `five_hour` and `seven_day` exist.
- **Per-window cost.** Windows carry percentages and reset times, never dollars.

`five_hour` is also absent until the API reports it, so the status line shows a
`-- not reported yet` meter rather than a fake zero.

## JSON parsing

The payload is read by `jq` if present, otherwise `node`, and the choice is
detected with `command -v` (a builtin, so it costs no fork). Both emit the same
unit-separated field line, so everything downstream is parser-agnostic, and a
parity test renders the same payloads through both to keep the two
implementations from drifting.

| Parser | Startup | Whole redraw |
|---|---|---|
| `jq` | ~11ms | ~70ms |
| `node` | ~51ms | ~124ms |
| neither | — | degraded line |

`SL_PARSER=jq|node` forces one. With neither installed the line still shows the
directory and git state, followed by `needs jq or node` — it does not go blank.

One trap worth remembering: arithmetic on a missing field aborts the whole `jq`
program, and every field then comes back empty, which blanks the line rather
than dropping one value. `prompt_cache` is absent until the first cached
request, so `.prompt_cache.hit_ratio * 100` used to kill every fresh session.
Scale only *after* the null check.

## A new or just-cleared session

Before the first API response there is no `rate_limits` block at all and
`context_window.context_window_size` is `0`. Meters with nothing behind them
render a dim track with `--` and a reason (`new session`, `not reported yet`)
instead of a fabricated `0%`. The windows populate on the first reply.

## Colour thresholds

Percentages run through four steps, set as `yellow,orange,red` boundaries.

| Key | Default | Applies to |
|---|---|---|
| `STEPS` | `50,75,90` | 5-hour, weekly, month |
| `CTX_STEPS` | follows `STEPS` | the context meter alone |
| `WK_PACE_STEPS` | `50,100,150` | the weekly pace chip, as `under,over,hot` |

The context window is separable because it fills on a different curve from a
rolling quota — a context that is 40% full is worth noticing long before a
usage window at 40% is. Values must be three ascending percentages in 1–100;
`slconf.py` rejects anything else before it is written.

Pace is scaled differently, because 1.0x is the meaningful line rather than
100% of a capacity: green at or under `1.0x`, then `1.25x`, `1.5x`.

## Pacing arithmetic

The month meter (Enterprise seats only — see **Usage tail by seat** below)
shows month-to-date against the cap, plus a projected month-end once that
projection would exceed the cap. Worked through for a $750 budget in a month
with 22 working days, on the third working day, having spent $112.50:

| Step | Value |
|---|---|
| Budget | $750.00 |
| Working days in the month | 22 |
| Working days elapsed | 3 |
| Spent this month | $112.50 |
| Projected month-end — 112.50 ÷ 3 × 22 | **$825.00** |

The projection only renders when it clears the cap (`$825 > $750` here); a
month trending under budget shows the plain `mo NN% of $cap` meter with
nothing appended. Working days are counted by deriving each day's weekday
from today's, entirely in shell arithmetic. `WORKDAYS=all` counts all seven
days instead.

### The ledger

`~/.claude/.statusline-ledger` holds the month total, today's total, and a
per-session cumulative baseline so a delta is only ever counted once:

```
month 2026-09
total 37500000          # micro-dollars, so the shell needs no float math
day 2026-09-03 6800000
s <session-id> <micro> <last-seen-epoch>
```

Behaviour worth knowing:

- Session baselines **survive a month rollover** on purpose. A session running
  across midnight on the 1st contributes only its post-rollover spend, not its
  whole cumulative cost.
- Session entries are pruned after 35 days.
- A baseline **never decreases**. A resume or a replayed payload can report less
  than was last seen; clamping the delta to zero is not enough, because storing
  the lower figure would make the next render re-add the whole difference.
- It **counts forward from when you enable it** and cannot backfill.
- Concurrent sessions each write it; the write is atomic via a temp file and
  rename, so a torn read is not possible, but a simultaneous write can lose one
  session's delta. Being a few cents out is acceptable for a pacing figure.

## Git state glyphs

| Glyph | Meaning |
|---|---|
| `!3` | 3 unmerged (conflicted) paths — shown first, in red |
| `+3` | 3 staged |
| `~3` | 3 with unstaged changes |
| `?3` | 3 untracked |
| `↑2` `↓1` | Commits ahead of / behind upstream |
| `⊘` | Branch has no upstream |
| `⇋ REBASE 1/2` | Operation in progress, with position |
| `⧉ name` / `🌳 name` | Inside a linked worktree |
| *(no mark)* | Clean — the branch simply stays green |

An unmerged path counts as a conflict, not as staged *and* unstaged at once —
otherwise the one state that blocks you is hidden among ordinary edits.

## Clickable path

The folder carries an OSC 8 hyperlink to its directory, the Jira key links to
the issue, and the PR links to its URL. Claude Code strips these sequences when
it measures the line's visible width, so **a link costs zero columns**. Terminals
without OSC 8 support ignore the sequence and show plain text. `LINKS=off`
removes them.

## Terminal caveats

- **No Nerd Font required.** Both glyph sets use standard Unicode or emoji.
- Emoji are double-width. The `visible()` width helper in `slconf.py` accounts
  for that, which is why reported column counts match reality.
- `git` plus either `jq` or `node` is required; see **JSON parsing** above.
- The context/spend line alone reaches ~75 columns on a Team seat; the weekly
  pace chip and a red context chip each add a few more.

## Bars

`BARS` picks the glyph pair every meter draws with: `blocks` (`▓░`) or `rule`
(`━`, dim remainder), sized by `BAR_WIDTH`/`RULE_W`. The inline context gauge
takes the same glyph pair, sized separately by `CTX_BAR_W` (six cells; `0`
drops it) and rounded rather than floored, since at that width a floored cell
reads a sixth behind the figure next to it.

## The layout

Two to three lines. Line one is repo, branch, the ticket, and the model; line
two is context and spend, always present; line three is exceptions in a fixed
order and is omitted when empty.

### Line one: repo, ticket, model

| Segment | Source | Renders |
|---|---|---|
| Folder, worktree | `workspace.current_dir`, `worktree.name` / `.git` file | just the folder you're in, not the whole path; `⧉ impl-cwng-16152` (`🌳` under emoji) in a linked worktree |
| Branch | one `git status` | introduced by `I_BR` (`⎇`, `🌿` under emoji) in place of a separator; green when clean; amber with `+n ~n ?n` marks when not; `↑ ↓ ⊘` divergence always dim |
| Jira key | `[A-Z][A-Z0-9]{1,9}-[0-9]+` anywhere in the branch | violet, bold, linked to `JIRA_SITE/browse/KEY` when that is set; status in dim from the cache |
| PR | `pr.number`, `.review_state` | quiet status chip: `approved` dim, `changes requested` in red, anything else dim |
| Model, effort | `model.id`, `effort.level` | last on the row: `opus-5 high`; the level is spelled out (`low medium high xhigh max`); tier chips as above |

### Line two: context and spend

| Segment | Source | Renders |
|---|---|---|
| Agent | `agent.name` | `agent builder`, only when a subagent is active |
| Context | `context_window.used_percentage` | a `CTX_BAR_W`-cell gauge in the `BARS` glyphs, then the figure; both plain, amber at `CTX_STEPS[1]`, red at `CTX_STEPS[2]` |
| Usage tail | seat-dependent, see below | never hidden |

### Usage tail by seat

`SEAT=auto` maps the cached plan from `~/.claude.json` to `enterprise` when the
organisation type contains "enterprise", else `team`. Force it with
`SEAT=team|enterprise`.

- **team**: `5h 80% resets 4:52pm wk 47% → 118%`. Each figure runs through
  `STEPS` (plain below the amber step). At or past amber, the 5-hour window
  follows with the **wall-clock time** it resets at (`resets 4:52pm`, via
  `_at()` — pure arithmetic against `TZOFF`, no `date` fork) and the week
  follows with a **countdown** instead (`resets 2h`, via `_until()`) — the
  5-hour window resets several times a day, where a clock time answers "is
  that before I leave," and the week resets once, days out, where a countdown
  is the more useful shape. The `→ 118%` chip is the weekly burn-rate projection: usage gained
  since the window's anchor, extrapolated over the working time left and added
  to the current figure, paced on **working time only** — any 7-day window
  covers each weekday exactly once, so a full window is always five working
  days (`WORKDAYS=all` paces over all seven instead). It renders green at or
  below `WK_PACE_STEPS[0]` (pacing well under the week), nothing through the
  on-track band, amber above `WK_PACE_STEPS[1]`, and red at `WK_PACE_STEPS[2]`
  or when the week itself is already red. Suppressed for the first six working
  hours since the anchor, and by `SHOW_WK_PACE=off`.
- **enterprise**: `$612 of 750 → $790`. Month to date from the ledger, the cap
  (`MONTHLY_LIMIT_USD`, defaulting to 750 in this layout), and the projected
  month-end: `mtd × working days in month ÷ working days elapsed`. The
  projection turns amber when it exceeds the cap; once spend itself passes the
  cap the tail reads `$781 of 750 over` in red. `slconf.py backfill` seeds the
  ledger from this month's transcripts using a model rate table shipped by
  some other installed plugin (any `skills/my-usage/scripts/rates.py`), so
  pricing has one source of truth rather than a second hardcoded copy. Without
  one, backfill declines and the ledger counts forward from now. It deduplicates
  API responses by
  `requestId`, and writes per-session baselines so live sessions are not
  double counted.

### Mid-window resets (Team seat)

Anthropic occasionally zeroes a Team seat's 5-hour or weekly usage part-way
through, without moving the window's reset time — a support adjustment, seen a
few times a year. The harness passes that figure straight through, so the
gauge drops to a low percentage and counts back up under the old reset time.
Without accounting for it, the weekly projection still assumed the window
began seven days before the reset, divided a small post-reset usage by that
large nominal elapsed time, and read as far calmer than the real burn rate.

The status line now tracks each window's high-water mark in
`~/.claude/.statusline-windows`. A reading that falls at least 5 points, and
to under half, of that mark is treated as a reset: the projection's anchor
moves to the moment the drop was noticed, and the gauge carries a dim `I_RST`
mark for the rest of the window (`5h 9%↻ wk 30%↻`) so the drop reads as a reset, not as
a sudden idle period. The `→ N%` chip then extrapolates only the usage gained
since that anchor, over the working time remaining, rather than assuming a
full nominal window. Ordinary usage growth within a window is unaffected — the
mark simply rises with it, and nothing is written unless something changed.
The state file is one line per redraw at most, keyed by each window's
`resets_at`, so a new window (a real reset) starts the mark over on its own.

### Line three: exceptions

| Order | Segment | Shows when | Source |
|---|---|---|---|
| 1 | PR | `pr.review_state` is not approved: red `changes requested`, amber anything else | payload |
| 2 | drift | the plugin named by `WATCH_PLUGIN` is behind its marketplace: `acme plugin 2 behind /plugin update acme`. Unset, the segment never renders | cache `drift`; compare API for a GitHub marketplace, `git rev-list` for a directory one |

### Cache and refresh protocol

Cache files live in `~/.claude/.statusline-cache/<name>`:

```
<expires-epoch>
field<US>field<US>field
```

The renderer serves whatever is there, stale or not, and when the expiry has
passed it writes `<name>.lock` and spawns
`python3 ~/.claude/statusline-refresh.py <segment> [args]` fully detached
(`nohup`, all descriptors redirected) so Claude Code is never left waiting on a
child. A lock younger than 90 s suppresses another spawn. The refresher writes
the new file atomically and removes the lock. An unavailable source (no `gh`
login, no Jira token, unknown plugin) writes an empty body with a long TTL, so
the segment stays silent and the source is not hammered.

### Cost of a redraw

One `git status`, one payload parse, and zero network — the remote segments are
served from cache and refreshed by a detached process. Four forks all told
(`cat`, `date`, `git status`, and the parser). Measured at about 70 ms with jq,
over ten redraws.
