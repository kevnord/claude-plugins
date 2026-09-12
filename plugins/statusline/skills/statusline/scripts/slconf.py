#!/usr/bin/env python3
"""Install and configure the Claude Code status line.

Subcommands:
  install [--force]        copy the runtime into ~/.claude, seed the config,
                           wire settings.json (backed up first)
  show                     effective config, with where each value came from
  set KEY=VALUE ...        validate and write config keys, then preview
  unset KEY ...            drop keys back to their defaults
  preview [KEY=VALUE ...]  render synthetic scenarios; --scenario picks one
  preset NAME              apply a named bundle: default | quiet
  backfill                 seed this month's ledger from local transcripts
                           (Enterprise seats; needs a my-usage rate table)
  budget [AMOUNT]          set an exact monthly budget (or --daily RATE,
                           --off); with no argument, show the current one
  gallery                  render each option side by side so you can pick;
                           --dimension style|bars|icons, --scenario
  doctor                   check dependencies and wiring
  uninstall                remove the statusLine key (leaves files in place)

Every value is validated before it is written, so a typo cannot leave the
status line broken.
"""

import argparse
import calendar
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata

HOME = os.path.expanduser("~")
CLAUDE = os.path.join(HOME, ".claude")
CONF = os.path.join(CLAUDE, "statusline.conf")
DEST = os.path.join(CLAUDE, "statusline.sh")
SETTINGS = os.path.join(CLAUDE, "settings.json")
LEDGER = os.path.join(CLAUDE, ".statusline-ledger")
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "statusline.sh")
REFRESH_SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "statusline-refresh.py")
REFRESH_DEST = os.path.join(CLAUDE, "statusline-refresh.py")
SL_CACHE = os.path.join(CLAUDE, ".statusline-cache")

# key -> (validator, default, one-line help)
ONOFF = ("on", "off")


def _int_in(lo, hi):
    def v(x):
        return x.isdigit() and lo <= int(x) <= hi
    return v, f"integer {lo}-{hi}"


def _one_of(*vals):
    return (lambda x: x in vals), " | ".join(vals)


def money_norm(x):
    """Accept $ and thousands separators; return a bare decimal string."""
    return x.strip().lstrip("$").replace(",", "").replace("_", "").strip()


def _money(x):
    x = money_norm(x)
    return bool(re.fullmatch(r"\d+(\.\d{1,2})?", x)) and float(x) > 0


NORMALIZE = {"MONTHLY_LIMIT_USD": money_norm}


def _steps(x):
    """Three ascending percentages: yellow,orange,red."""
    parts = [q.strip() for q in x.split(",")]
    if len(parts) != 3 or not all(q.isdigit() for q in parts):
        return False
    n = [int(q) for q in parts]
    return all(1 <= q <= 100 for q in n) and n[0] < n[1] < n[2]


SPEC = {
    "BARS":      (*_one_of("rule", "blocks"), "blocks", "gauge style for the meters"),
    "RULE_W":    (*_int_in(4, 40), "10", "rule cells when BARS=rule"),
    "BAR_WIDTH": (*_int_in(3, 20), "6", "block cells when BARS=blocks"),
    "CTX_BAR_W": (*_int_in(0, 12), "6", "cells in the inline ctx gauge (0 = off)"),
    "ICONS":     (*_one_of("emoji", "minimal"), "emoji", "glyph set"),
    "LINKS":     (*_one_of(*ONOFF), "on", "OSC 8 hyperlinks on the path and PR"),
    "MONTHLY_LIMIT_USD": (_money, "money > 0", "", "your monthly budget; enables month + pacing"),
    "WORKDAYS":  (*_one_of("mon-fri", "all"), "mon-fri", "days the budget is spread across"),
    "STEPS":     (_steps, "yellow,orange,red", "50,75,90", "colour steps for the usage windows"),
    "CTX_STEPS": (_steps, "yellow,orange,red", "", "colour steps for the context meter (else STEPS)"),
    "WK_PACE_STEPS": (_steps, "under,over,hot", "50,100,150", "steps for the weekly pace chip"),
    "HILITE_MODEL": (*_one_of(*ONOFF), "on", "filled model-tier chip (Haiku/Sonnet/Opus/Fable)"),
    "SEP":       (*_one_of("bar", "dot", "space"), "bar", "separator between segments"),
    "SEAT":      (*_one_of("auto", "team", "enterprise"), "auto", "which usage tail (auto reads ~/.claude.json)"),
    "SHOW_JIRA":   (*_one_of(*ONOFF), "on", "Jira key + status from the branch name"),
    "SHOW_PR":     (*_one_of(*ONOFF), "on", "PR needing you (changes requested / review pending)"),
    "SHOW_WK_PACE": (*_one_of(*ONOFF), "on", "weekly burn-rate projection chip"),
    "SHOW_DRIFT":  (*_one_of(*ONOFF), "on", "watched plugin behind its marketplace (needs WATCH_PLUGIN)"),
    "JIRA_SITE":   (lambda x: x.startswith("https://"), "https://... URL", "", "your Jira site, for links and status"),
    "WATCH_PLUGIN": (lambda x: "@" in x, "plugin@marketplace", "", "plugin whose drift to watch"),
}

PRESETS = {
    "default": {"SEP": "bar", "SHOW_JIRA": "on", "SHOW_PR": "on",
                "SHOW_DRIFT": "on", "STEPS": "50,75,90",
                "CTX_STEPS": "50,70,85"},
    "quiet":   {"SEP": "bar", "SHOW_JIRA": "on", "SHOW_PR": "on",
                "SHOW_DRIFT": "off"},
}
ORDER = list(SPEC)

# Pre-rename spellings. Accepted wherever a key is, and rewritten in place by
# install, so nobody has to hand-edit a config over a rename.
ALIASES = {"IL_PLUGIN": "WATCH_PLUGIN"}

# Keys that used to mean something and no longer do. Named rather than merely
# unknown, so an old config gets an explanation instead of "unknown key", and
# install clears them out instead of leaving a line that reads as live.
RETIRED = {
    "SHOW_IMPL":        "the implement-ticket segment was removed",
    "IMPL_HOME":        "the implement-ticket segment was removed",
    "IMPL_MAX":         "the implement-ticket segment was removed",
    "IMPL_SCAN":        "the implement-ticket segment was removed",
    "IMPL_STALE_MIN":   "the implement-ticket segment was removed",
    "IMPL_ABANDON_MIN": "the implement-ticket segment was removed",
    "SHOW_CI":          "the CI segment was removed",
    "SHOW_COST":        "cost feeds the Enterprise month meter; it has no segment of its own",
    "SHOW_TOKENS":      "the token segment was removed",
    "SHOW_CACHE":       "the cache segment was removed",
    "SHOW_PLAN":        "the plan segment was removed",
    "STYLE":            "there is one layout now, so there is nothing to switch",
}


def canon(key):
    return ALIASES.get(key, key)


def retire_conf():
    """Comment out retired keys in the config. Returns {key: reason}."""
    if not os.path.exists(CONF):
        return {}
    text = open(CONF, encoding="utf-8").read()
    done = {}
    for key, why in RETIRED.items():
        pat = re.compile(rf"^(\s*){key}(\s*=.*)$", re.M)
        if pat.search(text):
            text = pat.sub(rf"\1# retired: {key}\2", text)
            done[key] = why
    if done:
        open(CONF, "w", encoding="utf-8").write(text)
    return done


def migrate_conf():
    """Rewrite pre-rename keys in the config, comments and all. Returns them."""
    if not os.path.exists(CONF):
        return {}
    text = open(CONF, encoding="utf-8").read()
    done = {}
    for old, new in ALIASES.items():
        pat = re.compile(rf"^(\s*#?\s*){old}(\s*=)", re.M)
        if pat.search(text):
            text = pat.sub(rf"\1{new}\2", text)
            done[old] = new
    if done:
        open(CONF, "w", encoding="utf-8").write(text)
    return done


def spec(key):
    """Return (validator, syntax, default, help) for a key."""
    v, syn, dflt, hlp = SPEC[key]
    return v, syn, dflt, hlp


# ── config file ─────────────────────────────────────────────────────────────
def read_conf(path=CONF):
    """Parse KEY=VALUE lines, ignoring comments. Returns {key: value}."""
    out = {}
    if not os.path.exists(path):
        return out
    for line in open(path, encoding="utf-8"):
        m = re.match(r"^\s*([A-Z_]+)\s*=\s*([^#\n]*)", line)
        if m and canon(m.group(1)) in SPEC:
            out[canon(m.group(1))] = m.group(2).strip()
    return out


def write_keys(updates, removals=()):
    """Set/remove keys in place.

    A key that exists only as a commented example is uncommented and set where
    it stands, so a value stays next to the comment that explains it. Unsetting
    re-comments the line rather than deleting it, keeping that documentation.

    Pre-rename keys migrate first, so a legacy line is renamed where it stands
    instead of being left behind to contradict the new one.
    """
    migrate_conf()
    lines = open(CONF, encoding="utf-8").read().splitlines(True) if os.path.exists(CONF) else []
    live = re.compile(r"^(\s*)([A-Z_]+)(\s*=\s*)([^#\n]*)(.*)$")
    commented = re.compile(r"^(\s*)#\s*([A-Z_]+)\s*=\s*([^#\n]*)(.*)$")
    seen = set()
    out = []
    for line in lines:
        m = live.match(line)
        if m and m.group(2) in SPEC:
            key = m.group(2)
            if key in removals:
                out.append(f"#{key}={m.group(4).strip()}{m.group(5).rstrip(chr(10))}\n")
                continue
            if key in updates and key not in seen:
                tail = m.group(5).rstrip("\n")
                gap = " " * max(1, 21 - len(key) - 1 - len(updates[key])) if tail else ""
                out.append(f"{m.group(1)}{key}={updates[key]}{gap}{tail}\n")
                seen.add(key)
                continue
            out.append(line)
            continue
        c = commented.match(line)
        if c and c.group(2) in SPEC and c.group(2) in updates and c.group(2) not in seen:
            key = c.group(2)
            tail = c.group(4).rstrip("\n")
            gap = " " * max(1, 21 - len(key) - 1 - len(updates[key])) if tail else ""
            out.append(f"{c.group(1)}{key}={updates[key]}{gap}{tail}\n")
            seen.add(key)
            continue
        out.append(line)
    for key in ORDER:
        if key in updates and key not in seen:
            out.append(f"{key}={updates[key]}\n")
    os.makedirs(CLAUDE, exist_ok=True)
    with open(CONF, "w", encoding="utf-8") as fh:
        fh.write("".join(out))


def effective():
    conf = read_conf()
    rows = []
    for key in ORDER:
        _v, _syn, dflt, hlp = spec(key)
        if key in conf and conf[key] != "":
            rows.append((key, conf[key], "config", hlp))
        else:
            rows.append((key, dflt or "(unset)", "default", hlp))
    return rows


# ── rendering / width ───────────────────────────────────────────────────────
STRIP = re.compile(r"\x1b\[[\d;]*m|\x1b\]8;[^\x07\x1b]*(?:\x07|\x1b\\)")


def visible(s):
    """Width in terminal cells, ignoring the escapes Claude Code strips."""
    s = STRIP.sub("", s)
    n = 0
    for ch in s:
        if unicodedata.east_asian_width(ch) in ("W", "F"):
            n += 2
        elif 0x1F300 <= ord(ch) <= 0x1FAFF or 0x2600 <= ord(ch) <= 0x27BF:
            n += 2
        elif unicodedata.combining(ch):
            pass
        else:
            n += 1
    return n


def payload(scenario, cwd):
    now = int(time.time())
    p = {
        "session_id": "PREVIEW",
        "cwd": cwd,
        "model": {"id": "claude-opus-5", "display_name": "Opus 5"},
        "effort": {"level": "high"},
        "workspace": {"current_dir": cwd, "project_dir": cwd, "added_dirs": []},
        "version": "preview",
        "output_style": {"name": "default"},
        "cost": {"total_cost_usd": 7.5, "total_duration_ms": 0,
                 "total_api_duration_ms": 0, "total_lines_added": 0,
                 "total_lines_removed": 0},
        "context_window": {
            "total_input_tokens": 212000, "total_output_tokens": 1500,
            "context_window_size": 1000000, "used_percentage": 21,
            "remaining_percentage": 79,
            "current_usage": {"input_tokens": 2, "output_tokens": 1500,
                              "cache_creation_input_tokens": 900,
                              "cache_read_input_tokens": 211000}},
        "exceeds_200k_tokens": False,
        "prompt_cache": {"warm": True, "caching_observed": True, "ttl": "1h",
                         "expires_at": now + 3600, "requests": 23, "misses": 0,
                         "expected_rebuilds": 0, "hit_ratio": 0.98,
                         "cache_write_tokens": 1000, "miss_recache_tokens": 0,
                         "last_miss_at": None, "recache_tokens_if_cold": 212000},
        "fast_mode": False,
        "thinking": {"enabled": True},
        "rate_limits": {
            "five_hour": {"used_percentage": 26, "resets_at": now + 9900},
            "seven_day": {"used_percentage": 28, "resets_at": now + 518400}},
    }
    if scenario == "load":
        p["context_window"]["used_percentage"] = 61
        p["rate_limits"]["five_hour"] = {"used_percentage": 78, "resets_at": now + 2700}
        p["rate_limits"]["seven_day"] = {"used_percentage": 94, "resets_at": now + 320000}
        p["fast_mode"] = True
        p["pr"] = {"number": 412, "url": "https://github.com/example/repo/pull/412",
                   "review_state": "APPROVED"}
    elif scenario == "nofh":
        del p["rate_limits"]["five_hour"]
    elif scenario in ("quiet", "alert", "enterprise"):
        p["context_window"]["used_percentage"] = 38
        p["rate_limits"]["five_hour"] = {"used_percentage": 24, "resets_at": now + 9000}
        p["rate_limits"]["seven_day"] = {"used_percentage": 47, "resets_at": now + 500000}
        p["session_id"] = "PREVIEW"
        if scenario == "alert":
            p["context_window"]["used_percentage"] = 71
            p["rate_limits"]["seven_day"] = {"used_percentage": 82, "resets_at": now + 90000}
            p["pr"] = {"number": 88, "url": "https://github.com/example/repo/pull/88",
                       "review_state": "CHANGES_REQUESTED"}
        if scenario == "enterprise":
            p["rate_limits"] = {}
    return json.dumps(p)


SCENARIOS = {
    "quiet":  ("Quiet: clean tree, nothing needs you", "quiet"),
    "alert":  ("Bad day: changes requested, plugin behind", "alert"),
    "enterprise": ("Enterprise seat: month spend and pace against the $750 default", "enterprise"),
    "now":    ("Typical session", "now"),
    "budget": ("With the month budget and pacing", "now"),
    "load":   ("Under load - 78% of 5h, 94% of the week, PR open, fast mode", "load"),
    "nofh":   ("Before the 5-hour window reports", "nofh"),
}

# Scenarios rendered against a throwaway git repo and pre-seeded caches, so the
# branch, ticket and drift segments show something rather than blanks.
FIXTURE_SCENARIOS = ("quiet", "alert", "enterprise")


def render(scenario, overrides, cwd):
    """Run the real status line in a throwaway HOME so nothing is touched."""
    conf = dict(read_conf())
    conf.update(overrides)
    budget = conf.get("MONTHLY_LIMIT_USD", "")
    if scenario == "budget" and not budget:
        budget = "250"
        conf["MONTHLY_LIMIT_USD"] = budget
    if scenario != "budget":
        conf.pop("MONTHLY_LIMIT_USD", None)

    script = DEST if os.path.exists(DEST) else SRC
    fixture = scenario in FIXTURE_SCENARIOS
    if fixture:
        # so the preview demonstrates the segments even before they are configured
        conf.setdefault("JIRA_SITE", "https://example.atlassian.net")
        conf.setdefault("WATCH_PLUGIN", "example@example-marketplace")
    if scenario == "enterprise":
        conf["SEAT"] = "enterprise"
        conf.setdefault("MONTHLY_LIMIT_USD", "750")
        budget = conf["MONTHLY_LIMIT_USD"]
    elif fixture:
        conf["SEAT"] = "team"
        conf.pop("MONTHLY_LIMIT_USD", None)
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, ".claude"))
        if fixture:
            cwd = repo_fixture(tmp, scenario)
        # carry the real account file over so the seat/plan line is truthful
        real = os.path.join(HOME, ".claude.json")
        if os.path.exists(real):
            try:
                os.symlink(real, os.path.join(tmp, ".claude.json"))
            except OSError:
                pass
        with open(os.path.join(tmp, ".claude", "statusline.conf"), "w") as fh:
            fh.write("".join(f"{k}={v}\n" for k, v in conf.items() if v != ""))
        if scenario in ("budget", "enterprise"):
            b = float(budget)
            total = int(b * 0.15 * 1_000_000)
            today = int((b / 22) * 0.6 * 1_000_000)
            today_s = time.strftime("%Y-%m-%d")
            with open(os.path.join(tmp, ".claude", ".statusline-ledger"), "w") as fh:
                fh.write(f"month {time.strftime('%Y-%m')}\ntotal {total}\n"
                         f"day {today_s} {today}\ns PREVIEW 7500000 {int(time.time())}\n")
        env = dict(os.environ, HOME=tmp)
        r = subprocess.run(["bash", script], input=payload(SCENARIOS[scenario][1], cwd),
                           capture_output=True, text=True, env=env)
    return r.stdout.rstrip("\n"), r.stderr.strip()


US = "\x1f"


def repo_fixture(tmp, scenario):
    """A throwaway repo on a Jira-keyed branch, with the caches the scenario
    calls for, so the preview shows real segments rather than blanks."""
    repo = os.path.join(tmp, "payments-api")
    os.makedirs(repo)
    branch = "feature-PROJ-142-retry-backoff"
    subprocess.run(["git", "init", "-q", "-b", branch, repo], capture_output=True)
    subprocess.run(["git", "-C", repo, "-c", "user.email=p@example.com", "-c", "user.name=preview",
                    "commit", "-q", "--allow-empty", "-m", "preview"], capture_output=True)
    cache = os.path.join(tmp, ".claude", ".statusline-cache")
    os.makedirs(cache)
    now = int(time.time())

    def put(name, *fields):
        with open(os.path.join(cache, name), "w") as fh:
            fh.write(f"{now + 600}\n{US.join(fields)}\n")

    status = "In Review" if scenario == "alert" else "In Progress"
    put("jira-PROJ-142", status, "Retry backoff on gateway timeouts", "Preview User")
    put("drift", "0", "example")
    if scenario == "alert":
        put("drift", "2", "example")
    return repo


def do_preset(args):
    name = args.name
    if name not in PRESETS:
        raise SystemExit(f"error: unknown preset {name!r}; known: {', '.join(PRESETS)}")
    if not os.path.exists(CONF):
        os.makedirs(CLAUDE, exist_ok=True)
        open(CONF, "w", encoding="utf-8").write(DEFAULT_CONF)
    write_keys(dict(PRESETS[name]))
    print(f"preset {name}:")
    for k, v in PRESETS[name].items():
        print(f"  {k}={v}")
    if not os.path.exists(REFRESH_DEST):
        print("\n  note: the background refresher is not installed, so Jira")
        print("  and drift stay silent. Run: install")
    print()
    args.scenario = "quiet" if name == "quiet" else "alert"
    return do_preview(args, {})


# ── backfill: seed the ledger from local transcripts (Enterprise seats) ──────
def _rates_module():
    """Import a my-usage rates.py, if some installed plugin ships one, so
    pricing has one source of truth rather than a second hardcoded table."""
    import glob
    import importlib.util
    cands = glob.glob(os.path.join(CLAUDE, "plugins", "cache", "*", "*", "*", "skills", "my-usage", "scripts", "rates.py"))
    cands += glob.glob(os.path.join(CLAUDE, "plugins", "marketplaces", "*", "plugins", "*", "skills", "my-usage", "scripts", "rates.py"))
    try:
        mk = json.load(open(os.path.join(CLAUDE, "plugins", "known_marketplaces.json")))
        for m in mk.values():
            loc = m.get("installLocation")
            if loc:
                cands += glob.glob(os.path.join(loc, "plugins", "*", "skills", "my-usage", "scripts", "rates.py"))
    except (OSError, json.JSONDecodeError):
        pass
    cands = [c for c in cands if os.path.exists(c)]
    if not cands:
        return None
    path = max(cands, key=os.path.getmtime)
    spec_ = importlib.util.spec_from_file_location("sl_rates", path)
    mod = importlib.util.module_from_spec(spec_)
    spec_.loader.exec_module(mod)
    return mod


def do_backfill(args):
    from datetime import datetime, timezone
    rates = _rates_module()
    if rates is None:
        print("cannot backfill: no installed plugin provides a my-usage rate table")
        print("(skills/my-usage/scripts/rates.py), so there is no pricing to value sessions at.")
        print("The ledger will count forward from now instead.")
        return 1
    table = rates.load_rates()
    month = time.strftime("%Y-%m")
    today = time.strftime("%Y-%m-%d")
    start = datetime.strptime(month + "-01", "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp()
    seen = set()
    total = 0.0
    today_total = 0.0
    per_session = {}
    n_files = 0
    proj = os.path.join(CLAUDE, "projects")
    for root, _dirs, files in os.walk(proj):
        for fn in files:
            if not fn.endswith(".jsonl"):
                continue
            path = os.path.join(root, fn)
            try:
                if os.path.getmtime(path) < start:
                    continue
                fh = open(path, encoding="utf-8", errors="replace")
            except OSError:
                continue
            n_files += 1
            with fh:
                for line in fh:
                    if '"assistant"' not in line:
                        continue
                    try:
                        rec = json.loads(line)
                    except ValueError:
                        continue
                    if rec.get("type") != "assistant":
                        continue
                    ts_s = rec.get("timestamp") or ""
                    try:
                        ts = datetime.strptime(ts_s[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
                    except ValueError:
                        continue
                    if ts.timestamp() < start:
                        continue
                    msg = rec.get("message") or {}
                    key = rec.get("requestId") or msg.get("id")
                    if not key or key in seen:
                        continue
                    seen.add(key)
                    cost = rates.message_cost(msg.get("usage") or {}, msg.get("model") or "", ts, table)
                    if not cost:
                        continue
                    total += cost["total"]
                    sid = rec.get("sessionId") or ""
                    per_session[sid] = per_session.get(sid, 0.0) + cost["total"]
                    if ts.astimezone().strftime("%Y-%m-%d") == today:
                        today_total += cost["total"]
    if not n_files:
        print("no transcripts found under ~/.claude/projects; nothing to backfill")
        return 1
    micro = lambda v: int(round(v * 1_000_000))
    now = int(time.time())
    lines = [f"month {month}", f"total {micro(total)}", f"day {today} {micro(today_total)}"]
    for sid, v in per_session.items():
        if sid:
            lines.append(f"s {sid} {micro(v)} {now}")
    tmp = LEDGER + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    os.replace(tmp, LEDGER)
    print(f"backfilled {month} from {n_files} transcript files, {len(seen)} API responses")
    print(f"  month to date  ${total:,.2f}")
    print(f"  today          ${today_total:,.2f}")
    print(f"  sessions       {len(per_session)}")
    print("  (API-equivalent value at list rates; on a Team or Enterprise seat nothing is billed at this rate)")
    return 0


def do_preview(args, overrides):
    cwd = args.cwd or os.getcwd()
    names = list(SCENARIOS) if args.scenario == "all" else [args.scenario]
    if overrides:
        print("overrides: " + "  ".join(f"{k}={v}" for k, v in overrides.items()))
    for name in names:
        label = SCENARIOS[name][0]
        print(f"\n\033[1m{label}\033[0m \033[2m(synthetic payload)\033[0m")
        out, err = render(name, overrides, cwd)
        if err:
            print(f"  \033[31m{err}\033[0m")
        for line in out.split("\n"):
            print("  " + line)
        widths = ", ".join(f"line{i+1} {visible(l)}" for i, l in enumerate(out.split("\n")) if l)
        print(f"  \033[2m{widths} cols\033[0m")
    return 0


# ── budget ──────────────────────────────────────────────────────────────────
def workday_counts(mode, when=None):
    """(working days in the month, working days elapsed including today)."""
    t = time.localtime(when) if when else time.localtime()
    dim = calendar.monthrange(t.tm_year, t.tm_mon)[1]
    def counts(d):
        return mode == "all" or calendar.weekday(t.tm_year, t.tm_mon, d) < 5
    total = sum(1 for d in range(1, dim + 1) if counts(d))
    done = sum(1 for d in range(1, t.tm_mday + 1) if counts(d))
    return total, max(done, 1)


def budget_breakdown(amount, mode):
    total, done = workday_counts(mode)
    daily = amount / total if total else 0.0
    return {
        "month": time.strftime("%B %Y"),
        "workdays": total,
        "elapsed": done,
        "daily": daily,
        "expected": daily * done,
        "mode": mode,
    }


def print_breakdown(amount, mode):
    b = budget_breakdown(amount, mode)
    label = "all days" if mode == "all" else "Mon-Fri"
    print(f"  budget                     ${amount:,.2f}")
    print(f"  {b['month']} working days{'':<8}{b['workdays']}  ({label})")
    print(f"  one day's allotment        ${b['daily']:,.2f}")
    print(f"  working days elapsed       {b['elapsed']}")
    print(f"  on-plan spend by today     ${b['expected']:,.2f}")


def do_budget(args):
    conf = read_conf()
    mode = args.workdays or conf.get("WORKDAYS") or "mon-fri"

    if args.off:
        write_keys({}, removals={"MONTHLY_LIMIT_USD"})
        print("budget off - the month and pacing figures are hidden")
        return 0

    if args.amount is None and args.daily is None:
        cur = conf.get("MONTHLY_LIMIT_USD", "")
        if not cur:
            print("no budget set. Give an exact amount:")
            print("  slconf.py budget 1250          # exact monthly figure")
            print("  slconf.py budget --daily 50    # derive the month from a daily rate")
            return 0
        print(f"current budget: ${float(cur):,.2f}")
        print_breakdown(float(cur), mode)
        return 0

    if args.amount is not None and args.daily is not None:
        raise SystemExit("error: give either an amount or --daily, not both")

    if args.daily is not None:
        raw = money_norm(args.daily)
        if not re.fullmatch(r"\d+(\.\d{1,2})?", raw) or float(raw) <= 0:
            raise SystemExit(f"error: --daily {args.daily!r} is not a positive amount")
        total, _done = workday_counts(mode)
        amount = round(float(raw) * total, 2)
        print(f"${float(raw):,.2f}/day x {total} working days = ${amount:,.2f} this month")
        print("  (the working-day count changes month to month, so re-run --daily "
              "if you want it re-derived)")
    else:
        raw = money_norm(args.amount)
        if not re.fullmatch(r"\d+(\.\d{1,2})?", raw) or float(raw) <= 0:
            raise SystemExit(f"error: {args.amount!r} is not a positive amount "
                             "(try 1250, 1250.50, $1,250)")
        amount = float(raw)

    updates = {"MONTHLY_LIMIT_USD": f"{amount:.2f}".rstrip("0").rstrip(".")}
    if args.workdays:
        updates["WORKDAYS"] = args.workdays
    if not os.path.exists(CONF):
        os.makedirs(CLAUDE, exist_ok=True)
        open(CONF, "w", encoding="utf-8").write(DEFAULT_CONF)
    write_keys(updates)
    print(f"\nset MONTHLY_LIMIT_USD={updates['MONTHLY_LIMIT_USD']}")
    print_breakdown(amount, mode)
    ledger_note()
    seat = conf.get("SEAT", "auto")
    if seat != "enterprise":
        print("\n  Note: the month meter only appears on an Enterprise seat "
              "(SEAT=enterprise, or auto-detected). On a Team seat this budget "
              "is tracked but not shown.")
    print()
    args.scenario = "budget"
    return do_preview(args, {})


def ledger_note():
    if os.path.exists(LEDGER):
        return
    print("\n  Note: the ledger starts at zero now and counts forward. It cannot")
    print("  backfill spend from earlier this month, so `mo` will read low and the")
    print("  pace figure will be unreliable for the first few days.")


# ── gallery: show the options rather than describe them ─────────────────────
DIMENSIONS = {
    "bars":  ("BARS", ["rule", "blocks"],
              "thin rule, or solid blocks, for every meter"),
    "icons": ("ICONS", ["emoji", "minimal"],
              "emoji glyphs, or text labels and line-drawing characters"),
    "sep":    ("SEP", ["bar", "dot", "space"], "separator between segments"),
}


def do_gallery(args):
    cwd = args.cwd or os.getcwd()
    dims = list(DIMENSIONS) if args.dimension == "all" else [args.dimension]
    current = read_conf()
    for dim in dims:
        key, values, blurb = DIMENSIONS[dim]
        scen = args.scenario
        _v, _s, dflt, _h = spec(key)
        now = current.get(key, dflt)
        print(f"\n\033[1m{key}\033[0m \033[2m- {blurb}\033[0m")
        for val in values:
            ov = {key: val}
            if key == "SEP":
                scen = "alert"
            mark = " \033[36m(current)\033[0m" if val == now else ""
            print(f"\n  \033[1m{key}={val}\033[0m{mark}")
            out, err = render(scen, ov, cwd)
            if err:
                print(f"    \033[31m{err}\033[0m")
            for line in out.split("\n"):
                print("    " + line)
            widths = ", ".join(f"{visible(l)}" for l in out.split("\n") if l)
            print(f"    \033[2m{widths} cols   adopt with: slconf.py set {key}={val}\033[0m")
    print()
    return 0


# ── settings.json ───────────────────────────────────────────────────────────
def wire_settings():
    data = {}
    if os.path.exists(SETTINGS):
        shutil.copy2(SETTINGS, SETTINGS + ".bak")
        try:
            data = json.load(open(SETTINGS, encoding="utf-8"))
        except json.JSONDecodeError as exc:
            return f"settings.json is not valid JSON ({exc}); left untouched"
    want = {"type": "command", "command": DEST, "padding": 0}
    if data.get("statusLine") == want:
        return "settings.json already points at the status line"
    data["statusLine"] = want
    with open(SETTINGS, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    return f"settings.json statusLine -> {DEST} (backup at settings.json.bak)"


DEFAULT_CONF = """\
# ~/.claude/statusline.conf - read on every redraw; no restart needed.
# Managed by the statusline skill. `slconf.py show` lists effective values.

BARS=rule             # rule (thin) | blocks
RULE_W=12             # rule cells when BARS=rule
ICONS=emoji           # emoji | minimal
LINKS=on              # OSC 8 hyperlinks on the path and the PR
BAR_WIDTH=6           # block cells, when BARS=blocks
CTX_BAR_W=6           # cells in the inline ctx gauge (0 = off)

SEP=bar               # bar | dot | space - separator between segments
SEAT=auto             # auto | team | enterprise
SHOW_JIRA=on          # Jira key + status from the branch name
SHOW_PR=on            # PR needing you (changes requested / review pending)
SHOW_DRIFT=on         # a watched plugin behind its marketplace
SHOW_WK_PACE=on       # weekly burn-rate projection chip

# Remote segments. Both are unset by default and silent until you fill them in:
# without JIRA_SITE the branch's ticket key still shows, it just does not link
# or carry a status; without WATCH_PLUGIN the drift alert never appears.
#JIRA_SITE=https://your-site.atlassian.net
#WATCH_PLUGIN=plugin@marketplace

# Work-day pacing. Claude meters only a 5-hour and a 7-day window, so there is
# no monthly quota to report against. On a Team seat, set your own budget and
# the month meter appears alongside the usual windows; on an Enterprise seat
# (no window the harness reports) it appears automatically with a $750
# default. Measured from a local ledger that starts at zero when you enable
# it - it cannot backfill earlier spend.
#MONTHLY_LIMIT_USD=250
#WORKDAYS=mon-fri     # mon-fri | all
"""


def do_install(args):
    os.makedirs(CLAUDE, exist_ok=True)
    if not os.path.exists(SRC):
        print(f"error: runtime missing at {SRC}", file=sys.stderr)
        return 1
    fresh = not os.path.exists(DEST)
    shutil.copy2(SRC, DEST)
    os.chmod(DEST, 0o755)
    print(f"{'installed' if fresh else 'updated'}  {DEST}")
    if os.path.exists(REFRESH_SRC):
        shutil.copy2(REFRESH_SRC, REFRESH_DEST)
        os.chmod(REFRESH_DEST, 0o755)
        print(f"{'installed' if fresh else 'updated'}  {REFRESH_DEST}")

    if not os.path.exists(CONF) or args.force:
        with open(CONF, "w", encoding="utf-8") as fh:
            fh.write(DEFAULT_CONF)
        print(f"{'wrote' if not args.force else 'reset'}     {CONF}")
    else:
        print(f"kept      {CONF} (existing values preserved; --force to reset)")
        for old_key, new_key in migrate_conf().items():
            print(f"renamed   {old_key} -> {new_key}")
        for key, why in retire_conf().items():
            print(f"retired   {key} ({why})")

    print("wired     " + wire_settings())
    print()
    return do_doctor(args)


def do_uninstall(_args):
    if not os.path.exists(SETTINGS):
        print("no settings.json")
        return 0
    data = json.load(open(SETTINGS, encoding="utf-8"))
    if "statusLine" not in data:
        print("statusLine was not set")
        return 0
    shutil.copy2(SETTINGS, SETTINGS + ".bak")
    del data["statusLine"]
    with open(SETTINGS, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    print(f"removed statusLine from settings.json (backup at settings.json.bak)")
    print(f"left in place: {DEST}, {CONF}")
    return 0


def do_show(_args):
    print(f"config  {CONF}{'' if os.path.exists(CONF) else '   (absent - all defaults)'}")
    print(f"runtime {DEST}{'' if os.path.exists(DEST) else '   (not installed)'}")
    print()
    print(f"{'KEY':<20} {'VALUE':<12} {'SOURCE':<9} WHAT IT DOES")
    print("-" * 78)
    for key, val, src, hlp in effective():
        print(f"{key:<20} {val:<12} {src:<9} {hlp}")
    if os.path.exists(LEDGER):
        led = {}
        for line in open(LEDGER, encoding="utf-8"):
            parts = line.split()
            if parts and parts[0] in ("month", "total", "day"):
                led[parts[0]] = " ".join(parts[1:])
        if "total" in led:
            print(f"\nledger  month {led.get('month','?')}  "
                  f"month-to-date ${int(led['total'])/1_000_000:.2f}  "
                  f"today {led.get('day','-')}")
    return 0


def do_doctor(_args):
    ok = True

    def chk(good, label, detail=""):
        nonlocal ok
        print(f"  {'ok  ' if good else 'FAIL'}  {label}{('  - ' + detail) if detail else ''}")
        if not good:
            ok = False

    print("checks")
    jq, node = shutil.which("jq"), shutil.which("node")
    parser = "jq" if jq else ("node" if node else None)
    chk(parser is not None, "a JSON parser is available",
        "install jq (preferred) or node" if not parser
        else f"using {parser}" + ("" if jq else " - jq would be ~54ms faster per redraw"))
    chk(shutil.which("git") is not None, "git on PATH")
    chk(os.path.exists(DEST), "runtime installed", "" if os.path.exists(DEST) else "run: install")
    chk(os.path.exists(DEST) and os.access(DEST, os.X_OK), "runtime executable")
    wired = False
    if os.path.exists(SETTINGS):
        try:
            wired = json.load(open(SETTINGS, encoding="utf-8")).get("statusLine", {}).get("command") == DEST
        except json.JSONDecodeError:
            pass
    chk(wired, "settings.json statusLine wired", "" if wired else "run: install")

    bad = []
    for key, val in read_conf().items():
        v, syn, _d, _h = spec(key)
        if val != "" and not v(val):
            bad.append(f"{key}={val} (expected {syn})")
    chk(not bad, "config values valid", "; ".join(bad))

    if os.path.exists(DEST):
        out, err = render("now", {}, os.getcwd())
        chk(bool(out.strip()) and not err, "renders without error", err[:120])

    conf = read_conf()
    print()
    print("segments  (inactive segments render nothing; they never error)")

    def seg(active, label, detail):
        print(f"  {'on  ' if active else 'off '}  {label}{('  - ' + detail) if detail else ''}")

    seg(os.path.exists(REFRESH_DEST), "background refresher",
        "" if os.path.exists(REFRESH_DEST) else "run: install")
    gh_ok = False
    if shutil.which("gh"):
        gh_ok = subprocess.run(["gh", "auth", "status"], capture_output=True).returncode == 0
    watched = conf.get("WATCH_PLUGIN", "")
    drift_ok = gh_ok and bool(watched)
    seg(drift_ok, f"plugin drift{(' ' + watched) if watched else ''}",
        "" if drift_ok else ("install gh and run: gh auth login" if not gh_ok
                             else "set WATCH_PLUGIN=plugin@marketplace"))
    jira_ok = bool((os.environ.get("JIRA_EMAIL") or os.environ.get("ATLASSIAN_EMAIL"))
                   and (os.environ.get("JIRA_API_TOKEN") or os.environ.get("ATLASSIAN_API_TOKEN")))
    site = conf.get("JIRA_SITE", "")
    seg(jira_ok and bool(site), "Jira status (JIRA_SITE + JIRA_EMAIL + JIRA_API_TOKEN)",
        "" if (jira_ok and site) else
        ("set JIRA_SITE=https://your-site.atlassian.net; the key shows either way"
         if not site else "key still shows and links; status needs the two env vars"))
    plan = ""
    try:
        with open(os.path.join(CLAUDE, ".statusline-plan"), encoding="utf-8") as fh:
            parts = fh.read().split(US)
            plan = parts[2] if len(parts) > 2 else ""
    except OSError:
        pass
    seat = conf.get("SEAT", "auto")
    seg(True, f"usage tail  SEAT={seat}", f"detected plan: {plan or 'unknown until first redraw'}")
    if os.path.exists(LEDGER) or (seat == "enterprise"):
        seg(os.path.exists(LEDGER), "month ledger", "" if os.path.exists(LEDGER) else "run: backfill to seed it from transcripts")
    print()
    print("PASS" if ok else "FAIL - fix the items above")
    return 0 if ok else 1


def parse_assignments(items):
    out = {}
    for item in items:
        if "=" not in item:
            raise SystemExit(f"error: expected KEY=VALUE, got {item!r}")
        key, val = item.split("=", 1)
        key, val = canon(key.strip().upper()), val.strip()
        if key in RETIRED:
            raise SystemExit(f"error: {key} is retired - {RETIRED[key]}")
        if key not in SPEC:
            raise SystemExit(f"error: unknown key {key!r}\n       known: {', '.join(ORDER)}")
        v, syn, _d, _h = spec(key)
        if val != "" and not v(val):
            raise SystemExit(f"error: {key}={val!r} is invalid (expected {syn})")
        out[key] = NORMALIZE.get(key, lambda z: z)(val) if val != "" else val
    return out


def do_set(args):
    updates = parse_assignments(args.assignments)
    if not updates:
        raise SystemExit("error: nothing to set")
    if not os.path.exists(CONF):
        os.makedirs(CLAUDE, exist_ok=True)
        open(CONF, "w", encoding="utf-8").write(DEFAULT_CONF)
    write_keys(updates)
    for key, val in updates.items():
        print(f"set  {key}={val or '(cleared)'}")
    print()
    args.scenario = "budget" if "MONTHLY_LIMIT_USD" in updates and updates["MONTHLY_LIMIT_USD"] else "now"
    return do_preview(args, {})


def do_unset(args):
    keys = []
    for key in args.keys:
        key = canon(key.strip().upper())
        if key in RETIRED:
            raise SystemExit(f"error: {key} is retired - {RETIRED[key]}")
        if key not in SPEC:
            raise SystemExit(f"error: unknown key {key!r}")
        keys.append(key)
    write_keys({}, removals=set(keys))
    for key in keys:
        _v, _s, dflt, _h = spec(key)
        print(f"unset {key}  (back to default {dflt or '(off)'})")
    return 0


def main():
    ap = argparse.ArgumentParser(prog="slconf.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("install"); p.add_argument("--force", action="store_true")
    p.set_defaults(fn=do_install, scenario="now", cwd=None)
    sub.add_parser("show").set_defaults(fn=do_show)
    sub.add_parser("doctor").set_defaults(fn=do_doctor, scenario="now", cwd=None)
    sub.add_parser("uninstall").set_defaults(fn=do_uninstall)

    p = sub.add_parser("set"); p.add_argument("assignments", nargs="+")
    p.add_argument("--cwd"); p.set_defaults(fn=do_set)
    p = sub.add_parser("unset"); p.add_argument("keys", nargs="+")
    p.set_defaults(fn=do_unset)
    p = sub.add_parser("budget")
    p.add_argument("amount", nargs="?", help="exact monthly figure, e.g. 1250 or $1,250.50")
    p.add_argument("--daily", help="derive the monthly figure from a daily rate")
    p.add_argument("--workdays", choices=["mon-fri", "all"])
    p.add_argument("--off", action="store_true", help="turn the budget off")
    p.add_argument("--cwd"); p.set_defaults(fn=do_budget, scenario="budget")

    p = sub.add_parser("preset"); p.add_argument("name")
    p.add_argument("--cwd"); p.set_defaults(fn=do_preset)
    sub.add_parser("backfill").set_defaults(fn=do_backfill)

    p = sub.add_parser("gallery")
    p.add_argument("--dimension", choices=list(DIMENSIONS) + ["all"], default="all")
    p.add_argument("--scenario", choices=list(SCENARIOS), default="now")
    p.add_argument("--cwd"); p.set_defaults(fn=do_gallery)

    p = sub.add_parser("preview"); p.add_argument("assignments", nargs="*")
    p.add_argument("--scenario", choices=list(SCENARIOS) + ["all"], default="all")
    p.add_argument("--cwd"); p.set_defaults(fn=None)

    args = ap.parse_args()
    if args.cmd == "preview":
        return do_preview(args, parse_assignments(args.assignments))
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
