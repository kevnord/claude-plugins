# Status line

A two-to-three-line terminal readout for Claude Code — what you are working on,
what you have spent, and anything that needs you. One `git status` spawn, one
JSON parse, nothing over the network: about 70ms per redraw.

```
payments-api ⎇ feature-PROJ-142-retry-backoff │ PROJ-142 In Progress │ opus-5 high
ctx ━━━━━━ 38% │ 5h 24% 2h30m   wk 47% 5d18h → 118%
PR #412 changes requested │ acme plugin 2 behind
```

Line one is the repo, the branch, the ticket and PR found on it, and the model
answering. Line two is context and usage, always. Line three appears **only**
when something is actionable, and is otherwise absent rather than blank.

## Quick start

```
/statusline
```

That installs the runtime into `~/.claude/`, wires `settings.json` (backing it
up first), and runs the checks. Re-run it any time to upgrade — your config is
preserved.

Then ask for what you want in plain language: "make the meters solid blocks",
"use minimal icons", "set my monthly budget to 400", "my statusline looks
wrong". Before any look-and-feel change the skill renders the options as real
status lines so you pick from output, not prose.

## What it shows

| Segment | Detail |
|---|---|
| Repo and branch | Branch is green only when the tree is clean; `⧉ name` marks a linked worktree |
| Ticket | Any `PROJ-123` in the branch name, linked and with its live status |
| Model | Model id and effort level, in a chip coloured by tier |
| Context | Percentage of the context window behind a short gauge |
| Usage | The 5-hour and 7-day windows, with a burn-rate projection paced over working days — or a monthly budget meter |
| PR | The branch PR's review state; a request for changes escalates to line three |
| Plugin drift | A plugin you watch that has fallen behind its marketplace |

## Configuration

Everything lives in `~/.claude/statusline.conf`, read on every redraw — no
restart. `BARS`, `ICONS`, `SEP`, `RULE_W`, `BAR_WIDTH`, `CTX_BAR_W` and `LINKS`
set the look; `STEPS`, `CTX_STEPS` and `WK_PACE_STEPS` set the colour
thresholds; `SHOW_JIRA`, `SHOW_PR`, `SHOW_DRIFT` and `SHOW_WK_PACE` turn
segments off.

Two keys are unset out of the box, because only you know them:

- `JIRA_SITE` — your Atlassian site. Without it the branch's ticket key still
  shows; it just does not link or carry a status.
- `WATCH_PLUGIN` — the `plugin@marketplace` to watch for drift. Without it that
  alert never appears.

Live Jira status also needs `JIRA_EMAIL` + `JIRA_API_TOKEN` (or the
`ATLASSIAN_*` pair) in your environment. `/statusline doctor` reports exactly
which segments are live and what each silent one is missing.

## Requirements

`git`, plus either `jq` (preferred, ~11ms) or `node` (~51ms). `python3` for the
configuration CLI and the background refresher. `gh` only for plugin-drift on a
GitHub-hosted marketplace. With neither `jq` nor `node` the line does not go
blank — it says so.

Nothing is fetched during a redraw. Remote segments read a local cache and
spawn a detached refresher when it is stale, so a redraw never waits on the
network.
