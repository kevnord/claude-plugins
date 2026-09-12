#!/usr/bin/env python3
"""Background refresher for the status line's remote segments.

The status line itself never waits on the network. When a segment's cache under
~/.claude/.statusline-cache is missing or stale, the renderer spawns this script
detached and keeps serving the old value. This script fetches one segment and
rewrites its cache file atomically:

    <expires-epoch>\\n<field>\\x1f<field>...\\n

A source that is unavailable (no gh login, no Jira token, no such plugin) writes
an empty body with a long TTL, so the segment stays silent and is not retried
on every redraw.

    statusline-refresh.py jira    <KEY> <site-url>
    statusline-refresh.py drift   <plugin@marketplace>

Only python3 and, for the GitHub segments, the `gh` CLI are required.
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

US = "\x1f"
HOME = os.path.expanduser("~")
CACHE = os.path.join(HOME, ".claude", ".statusline-cache")
NOW = int(time.time())


def write(name, fields, ttl):
    os.makedirs(CACHE, exist_ok=True)
    body = US.join(str(f).replace("\n", " ").replace(US, " ") for f in fields)
    tmp = os.path.join(CACHE, f".{name}.{os.getpid()}")
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(f"{NOW + ttl}\n{body}\n")
    os.replace(tmp, os.path.join(CACHE, name))
    try:
        os.unlink(os.path.join(CACHE, f"{name.split('-')[0]}.lock"))
    except OSError:
        pass


def gh(*args, timeout=20):
    """Run gh and return stdout, or None when gh is missing or not logged in."""
    try:
        r = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=timeout)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if r.returncode != 0:
        return None
    return r.stdout


# ── jira ─────────────────────────────────────────────────────────────────────
def jira(key, site):
    """Status, summary and assignee for one issue. Credentials come from the
    same variables the implement-ticket plugin reads: JIRA_EMAIL / JIRA_API_TOKEN, or the
    ATLASSIAN_* pair."""
    email = os.environ.get("JIRA_EMAIL") or os.environ.get("ATLASSIAN_EMAIL")
    token = os.environ.get("JIRA_API_TOKEN") or os.environ.get("ATLASSIAN_API_TOKEN")
    name = f"jira-{key}"
    if not (email and token and site):
        write(name, [], 6 * 3600)
        return
    url = f"{site.rstrip('/')}/rest/api/3/issue/{key}?fields=status,summary,assignee"
    req = urllib.request.Request(url, headers={
        "Authorization": "Basic " + base64.b64encode(f"{email}:{token}".encode()).decode(),
        "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.load(resp)
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        write(name, [], 600)
        return
    f = data.get("fields") or {}
    status = ((f.get("status") or {}).get("name")) or ""
    summary = f.get("summary") or ""
    assignee = ((f.get("assignee") or {}).get("displayName")) or ""
    write(name, [status, summary, assignee], 300)


# ── plugin drift ─────────────────────────────────────────────────────────────
def drift(spec):
    """How many commits the installed plugin is behind its marketplace."""
    plug, _, market = spec.partition("@")
    try:
        inst = json.load(open(os.path.join(HOME, ".claude", "plugins", "installed_plugins.json")))
        mk = json.load(open(os.path.join(HOME, ".claude", "plugins", "known_marketplaces.json")))
    except (OSError, json.JSONDecodeError):
        write("drift", [], 86400)
        return
    entries = (inst.get("plugins") or {}).get(spec) or []
    src = ((mk.get(market) or {}).get("source") or {})
    sha = entries[0].get("gitCommitSha") if entries else None
    if not sha:
        write("drift", [], 86400)
        return
    behind = None
    if src.get("source") == "github" and src.get("repo"):
        out = gh("api", f"repos/{src['repo']}/compare/{sha}...HEAD", "--jq", ".ahead_by")
        if out and out.strip().isdigit():
            behind = int(out.strip())
    elif src.get("source") == "directory" and src.get("path"):
        try:
            r = subprocess.run(["git", "-C", src["path"], "rev-list", "--count", f"{sha}..HEAD"],
                               capture_output=True, text=True, timeout=10)
            if r.returncode == 0 and r.stdout.strip().isdigit():
                behind = int(r.stdout.strip())
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass
    if behind is None:
        write("drift", [], 6 * 3600)
        return
    write("drift", [str(behind), plug], 86400)


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    seg, args = argv[0], argv[1:]
    try:
        if seg == "jira" and len(args) >= 2:
            jira(args[0], args[1])
        elif seg == "drift" and args:
            drift(args[0])
        else:
            print(__doc__)
            return 2
    finally:
        # the renderer's lock is keyed by segment name; make sure it is cleared
        try:
            os.unlink(os.path.join(CACHE, f"{seg}.lock"))
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
