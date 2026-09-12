#!/bin/bash
# ~/.claude/statusline.sh — Claude Code status line
#
# Everything except git comes from the JSON the harness pipes in on stdin:
# model, effort, fast_mode, thinking, context_window, cost, prompt_cache,
# rate_limits.five_hour / .seven_day / .spend_limit, worktree, pr, agent.
# Git state is one `git status --branch --porcelain` spawn; the payload is read
# by jq or, failing that, node. The rest of the render is fork-free, so a
# redraw stays around 70ms with jq.
#
# Optional config, sourced if present: ~/.claude/statusline.conf
#   ICONS=emoji|minimal                  glyph set (default emoji)
#   BAR_WIDTH=6                          block-gauge cells
#   BARS=blocks|rule                     block gauges, or a thin rule
#   RULE_W=10                            rule cells when BARS=rule
#   CTX_BAR_W=6                          cells in the inline ctx gauge (0 = off)
#   MONTHLY_LIMIT_USD=250                your own budget; enables month + pacing
#                                        (auto-set to 750 on an Enterprise seat)
#   WORKDAYS=mon-fri|all                 which days the budget is spread across
#   LINKS=on|off                         OSC 8 hyperlinks on the path and PR
#   STEPS=50,75,90                       yellow,orange,red steps for the windows
#   HILITE_MODEL=on|off                  mark the model by tier as a filled
#                                        chip: Haiku grey, Sonnet green, Opus
#                                        yellow, Fable red (default on)
#   SHOW_WK_PACE=on|off                  weekly burn-rate projection, paced
#                                        over WORKDAYS (weekends excluded)
#   WK_PACE_STEPS=50,100,150             under,over,hot steps for that chip
#   CTX_STEPS=30,35,40                   the same, for the context meter only
#   SEP=bar|dot|space                    separator glyph between segments
#   SEAT=auto|team|enterprise            which usage windows to show
#   SHOW_PR=on|off, SHOW_JIRA=on|off, SHOW_DRIFT=on|off
#                                        the GitHub line and the alert line
#
# PACING. Claude meters only two windows (5-hour and 7-day), so there is no
# monthly quota to report against. Set MONTHLY_LIMIT_USD and this script spreads
# that budget across the working days of the current month and shows the
# month's share spent so far, with a projection once it lands on an Enterprise
# seat. Measured from a local month-to-date ledger in
# ~/.claude/.statusline-ledger, accumulated from each session's reported cost.
# It starts at zero when you enable it and counts forward; it cannot backfill.
#
# Requires: git, plus either jq (preferred) or node.

CONF="$HOME/.claude/statusline.conf"
[ -f "$CONF" ] && . "$CONF"
ICONS="${CC_SL_ICONS:-${ICONS:-emoji}}"
BAR_WIDTH="${BAR_WIDTH:-6}"
MONTHLY_LIMIT_USD="${MONTHLY_LIMIT_USD:-}"
WORKDAYS="${WORKDAYS:-mon-fri}"
LINKS="${LINKS:-on}"
# Colour steps as "yellow,orange,red" percentages. CTX_STEPS applies to the
# context meter alone, which fills on a different curve from a usage window;
# unset, it follows STEPS.
STEPS="${STEPS:-50,75,90}"
CTX_STEPS="${CTX_STEPS:-$STEPS}"
_r=${STEPS#*,};     S_Y=${STEPS%%,*};     S_O=${_r%%,*};  S_R=${_r#*,}
_r=${CTX_STEPS#*,}; C_Y=${CTX_STEPS%%,*}; C_O=${_r%%,*};  C_R=${_r#*,}
BARS="${BARS:-blocks}"
RULE_W="${RULE_W:-10}"
# A short gauge printed ahead of the context figure. 0 drops it.
CTX_BAR_W="${CTX_BAR_W:-6}"
SEP="${SEP:-bar}"                      # bar | dot | space
SEAT="${SEAT:-auto}"                   # auto | team | enterprise
SHOW_PR="${SHOW_PR:-on}"
SHOW_DRIFT="${SHOW_DRIFT:-on}"
SHOW_JIRA="${SHOW_JIRA:-on}"
SHOW_WK_PACE="${SHOW_WK_PACE:-on}"
HILITE_MODEL="${HILITE_MODEL:-on}"
# pace chip steps as "under,over,hot" percentages of the weekly window
WK_PACE_STEPS="${WK_PACE_STEPS:-50,100,150}"
_r=${WK_PACE_STEPS#*,}; W_U=${WK_PACE_STEPS%%,*}; W_O=${_r%%,*}; W_H=${_r#*,}
# Both are unset by default: the Jira key still shows without a site, it just
# does not link or carry a status, and drift stays silent until you name a plugin.
JIRA_SITE="${JIRA_SITE:-}"
WATCH_PLUGIN="${WATCH_PLUGIN:-}"
SL_CACHE="$HOME/.claude/.statusline-cache"
SL_REFRESH="$HOME/.claude/statusline-refresh.py"

input=$(cat)

# ── palette ──────────────────────────────────────────────────────────────────
e=$'\033['; E=$'\033'; ST=$'\033\\'; R="${e}0m"; B="${e}1m"; D="${e}2m"
GRN="${e}38;5;77m"; YEL="${e}38;5;221m"; ORG="${e}38;5;215m"; RED="${e}38;5;203m"
CYN="${e}38;5;80m"; BLU="${e}38;5;75m"; MAG="${e}38;5;176m"; GRY="${e}38;5;245m"
WHT="${e}38;5;253m"
# background variants, for bars drawn as coloured space rather than glyphs
bg() { RET="${e}48;5;${1}m"; }
BG_GRN="${e}48;5;108m"; BG_YEL="${e}48;5;179m"
BG_ORG="${e}48;5;173m"; BG_RED="${e}48;5;174m"; BG_GRY="${e}48;5;246m"
INK_ON="${e}38;5;235m"

# ── glyphs ───────────────────────────────────────────────────────────────────
if [ "$ICONS" = emoji ]; then
  I_BR="🌿"; I_WT="🌳"; I_5H="⏳"; I_WK="📅"; I_MO="🗓"; I_PR="🔀"
  I_RST="↻"; I_NOUP="⊘"; I_FAST="⚡"
  L_5H=""; L_WK=""; L_MO=""
else
  I_BR="⎇"; I_WT="⧉"; I_5H=""; I_WK=""; I_MO=""; I_PR="PR"
  I_RST="↻"; I_NOUP="⊘"; I_FAST="⚡"
  L_5H="5h "; L_WK="wk"; L_MO="mo"
fi

M_5H="${I_5H}${L_5H% }"; M_WK="${I_WK}${L_WK}"

# ── payload parsing ─────────────────────────────────────────────────────────
# jq is preferred (~11ms); node is the fallback (~51ms). Both emit one line of
# unit-separated fields, so everything downstream is parser-agnostic. With
# neither available the line degrades to directory and git state plus a hint,
# rather than going blank. Override with SL_PARSER=jq|node.
US=$'\x1f'
if [ -n "${SL_PARSER:-}" ]; then :
elif command -v jq   >/dev/null 2>&1; then SL_PARSER=jq
elif command -v node >/dev/null 2>&1; then SL_PARSER=node
else SL_PARSER=none
fi

_payload_jq() { printf '%s' "$input" | jq -r '
    def n(x): (x // "") | tostring;
    def p(x): (x | if . == null then "" else (floor|tostring) end);
    # scale-then-floor, but only when the value exists - multiplying a null
    # aborts the whole program and leaves every field empty
    def pc(x): (x | if . == null then "" else ((. * 100)|floor|tostring) end);
    [ n(.workspace.current_dir), n(.workspace.project_dir),
      n(.model.display_name), n(.effort.level),
      (if .fast_mode then "1" else "" end),
      (if .thinking.enabled == false then "off" else "" end),
      n(.model.id), n(.cost.total_duration_ms),
      p(.context_window.used_percentage), n(.context_window.total_input_tokens),
      n(.context_window.context_window_size), n(.cost.total_cost_usd),
      n(.session_id),
      p(.rate_limits.five_hour.used_percentage),   n(.rate_limits.five_hour.resets_at),
      p(.rate_limits.seven_day.used_percentage),   n(.rate_limits.seven_day.resets_at),
      p(.rate_limits.spend_limit.used_percentage), n(.rate_limits.spend_limit.resets_at),
      n(.worktree.name), n(.pr.number), n(.pr.review_state), n(.pr.url), n(.agent.name),
      n(.prompt_cache.ttl), pc(.prompt_cache.hit_ratio),
      "END" ] | map(tostring) | join("\u001f")'; }

_payload_node() { printf '%s' "$input" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
let j={};try{j=JSON.parse(s)}catch(e){}
const G=p=>p.split(".").reduce((a,k)=>(a==null?undefined:a[k]),j);
const n=p=>{const v=G(p);return v==null?"":String(v)};
const f=p=>{const v=G(p);return v==null?"":String(Math.floor(v))};
const c=p=>{const v=G(p);return v==null?"":String(Math.floor(v*100))};
process.stdout.write([
n("workspace.current_dir"),n("workspace.project_dir"),
n("model.display_name"),n("effort.level"),
G("fast_mode")?"1":"",G("thinking.enabled")===false?"off":"",
n("model.id"),n("cost.total_duration_ms"),
f("context_window.used_percentage"),n("context_window.total_input_tokens"),
n("context_window.context_window_size"),n("cost.total_cost_usd"),n("session_id"),
f("rate_limits.five_hour.used_percentage"),n("rate_limits.five_hour.resets_at"),
f("rate_limits.seven_day.used_percentage"),n("rate_limits.seven_day.resets_at"),
f("rate_limits.spend_limit.used_percentage"),n("rate_limits.spend_limit.resets_at"),
n("worktree.name"),n("pr.number"),n("pr.review_state"),n("pr.url"),n("agent.name"),
n("prompt_cache.ttl"),c("prompt_cache.hit_ratio"),
"END"].join("\x1f"))});'; }

# One process substitution, as before - routing through a variable would add a
# fork and a temp file to every redraw.
_payload() {
  case "$SL_PARSER" in
    jq)   _payload_jq   ;;
    node) _payload_node ;;
  esac; }

IFS="$US" read -r CWD PROJDIR MODEL EFFORT FAST THINK \
  MODEL_ID DUR_MS CTXPCT CTXIN CTXSZ COST SESSION \
  FH_PCT FH_RST WK_PCT WK_RST SL_PCT SL_RST \
  WT_NAME PR_NUM PR_STATE PR_URL AGENT CACHE_TTL CACHE_HIT _END \
  < <(_payload)

# Nothing parsed - keep the line useful instead of blank, and say why.
[ -z "$CWD" ] && CWD="$PWD"


read -r NOW MONTH TODAY DOM DOW YEAR MON TZO < <(date '+%s %Y-%m %Y-%m-%d %d %u %Y %m %z')
DOM=$(( 10#$DOM )); MON=$(( 10#$MON ))
# offset as seconds east of UTC, so an epoch can be bucketed into local days
TZOFF=0
if [ -n "$TZO" ]; then
  _tzs=${TZO:0:1}; _tzh=$(( 10#${TZO:1:2} )); _tzm=$(( 10#${TZO:3:2} ))
  TZOFF=$(( _tzh * 3600 + _tzm * 60 )); [ "$_tzs" = - ] && TZOFF=$(( -TZOFF ))
fi

# ── plan / seat (cached 12h; ~/.claude.json is large) ────────────────────────
# Also keyed on ~/.claude.json's mtime so a login/account switch — which
# rewrites that file — busts the cache immediately instead of waiting out the
# 12h window on stale plan data (e.g. a stale Enterprise budget after moving
# back to a Team seat).
PLAN=""
PC="$HOME/.claude/.statusline-plan"
CJ="$HOME/.claude.json"
_stat_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }
_cj_mtime=$(_stat_mtime "$CJ")
_fresh=""
if [ -f "$PC" ]; then
  IFS="$US" read -r _exp _cached_mtime PLAN < "$PC"
  if [ -n "$_exp" ] && [ "$_exp" -gt "$NOW" ] 2>/dev/null \
     && [ "$_cached_mtime" = "$_cj_mtime" ]; then
    _fresh=1
  fi
fi
if [ -z "$_fresh" ]; then
  # Only the plan name matters here (seat detection below keys off
  # "*Enterprise*"); the rate-limit tier isn't otherwise displayed.
  _plan_jq() { jq -r '
      (.oauthAccount.organizationType // "") as $ot
    | if   $ot == "claude_team"     then "Team"
      elif ($ot|test("enterprise")) then "Enterprise"
      elif ($ot|test("claude_max")) then "Max"
      else "" end' "$HOME/.claude.json" 2>/dev/null; }

  _plan_node() { node -e 'const fs=require("fs");let j={};try{j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"))}catch(e){}const o=(j.oauthAccount||{}).organizationType||"";process.stdout.write(o==="claude_team"?"Team":/enterprise/.test(o)?"Enterprise":/claude_max/.test(o)?"Max":"")' "$HOME/.claude.json" 2>/dev/null; }

  case "$SL_PARSER" in
    jq)   PLAN=$(_plan_jq)   ;;
    node) PLAN=$(_plan_node) ;;
    *)    PLAN=""            ;;
  esac
  printf '%s%s%s%s%s' "$((NOW + 43200))" "$US" "$_cj_mtime" "$US" "$PLAN" > "$PC" 2>/dev/null
fi

# ── seat for the il layout ───────────────────────────────────────────────────
# Team seats are metered by the 5-hour and weekly windows; Enterprise seats have
# no window the harness reports, so they get the month ledger with a default cap.
SL_SEAT="$SEAT"
if [ "$SL_SEAT" = auto ]; then
  case "$PLAN" in *Enterprise*) SL_SEAT=enterprise ;; *) SL_SEAT=team ;; esac
fi
if [ "$SL_SEAT" = enterprise ] && [ -z "$MONTHLY_LIMIT_USD" ]; then
  MONTHLY_LIMIT_USD=750
fi

# ── helpers: set RET, never fork ─────────────────────────────────────────────
RET=""
_step_color() { local p=${1:-0} y=$2 o=$3 r=$4
  if   [ "$p" -lt "$y" ]; then RET=$GRN
  elif [ "$p" -lt "$o" ]; then RET=$YEL
  elif [ "$p" -lt "$r" ]; then RET=$ORG
  else RET=$RED; fi; }

# usage windows, the month and the day allotment
_color() { _step_color "${1:-0}" "$S_Y" "$S_O" "$S_R"; }

# the context window, which can warrant tighter steps
_color_ctx() { _step_color "${1:-0}" "$C_Y" "$C_O" "$C_R"; }

_bar() { local p=${1:-0} w=${2:-10} f=${3:-▓} m=${4:-░} n i
  n=$(( p * w / 100 )); [ "$n" -gt "$w" ] && n=$w; [ "$n" -lt 0 ] && n=0
  RET=""; for ((i=0;i<n;i++)); do RET+=$f; done
  for ((i=n;i<w;i++)); do RET+=$m; done; }

_until() { local t=${1:-} s d h m
  RET=""; [ -z "$t" ] && return
  s=$(( t - NOW )); [ "$s" -lt 0 ] && s=0
  d=$(( s/86400 )); h=$(( (s%86400)/3600 )); m=$(( (s%3600)/60 ))
  if   [ "$d" -gt 0 ]; then printf -v RET '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf -v RET '%dh%02dm' "$h" "$m"
  else printf -v RET '%dm' "$m"; fi; }

# Local wall-clock time a reset lands at, e.g. 4:52pm. Arithmetic only - reuses
# TZOFF from startup rather than forking date, so this costs nothing in the
# render path even though it runs on every redraw once a window is hot.
_at() { local t=${1:-} secs h24 h12 m ap
  RET=""; [ -z "$t" ] && return
  secs=$(( (t + TZOFF) % 86400 ))
  h24=$(( secs / 3600 )); m=$(( (secs % 3600) / 60 ))
  ap=am; [ "$h24" -ge 12 ] && ap=pm
  h12=$(( h24 % 12 )); [ "$h12" -eq 0 ] && h12=12
  printf -v RET '%d:%02d%s' "$h12" "$m" "$ap"; }

# Working seconds between two epochs, weekends excluded (WORKDAYS=all counts
# every day). Walks local days, so a Friday evening is not charged to Saturday.
# Epoch day 0 is a Thursday, hence the +3 to land ISO 1=Mon .. 7=Sun.
_worked() { local a=$1 b=$2 d0 d1 d ds de lo hi
  RET=0; [ "$b" -le "$a" ] && return
  if [ "$WORKDAYS" = all ]; then RET=$(( b - a )); return; fi
  d0=$(( (a + TZOFF) / 86400 )); d1=$(( (b + TZOFF) / 86400 ))
  for (( d = d0; d <= d1; d++ )); do
    [ $(( (d + 3) % 7 + 1 )) -ge 6 ] && continue     # Saturday or Sunday
    ds=$(( d * 86400 - TZOFF )); de=$(( ds + 86400 ))
    lo=$a; [ "$ds" -gt "$lo" ] && lo=$ds
    hi=$b; [ "$de" -lt "$hi" ] && hi=$de
    [ "$hi" -gt "$lo" ] && RET=$(( RET + hi - lo ))
  done; }

# OSC 8 hyperlink. Claude Code strips these when measuring the status line's
# visible width, so a link costs no columns. Terminals without OSC 8 support
# ignore the sequence and just show the text.
_url_enc() { local u=${1//\%/%25}
  u=${u// /%20}; u=${u//\#/%23}; u=${u//\?/%3F}; RET=$u; }

_link() { local url=$1 text=$2
  if [ "$LINKS" != on ] || [ -z "$url" ]; then RET=$text; return; fi
  RET="${E}]8;;${url}${ST}${text}${E}]8;;${ST}"; }

_path_link() { local dir=$1 text=$2
  if [ "$LINKS" != on ] || [ -z "$dir" ]; then RET=$text; return; fi
  _url_enc "$dir"; _link "file://${RET}" "$text"; }

# dollars -> integer micro-dollars, so the ledger needs no float math
_micro() { local v=${1:-0} ip fp
  ip=${v%%.*}; fp=${v#*.}
  [ "$ip" = "$v" ] && fp=0
  fp="${fp}000000"; fp=${fp:0:6}
  RET=$(( ${ip:-0} * 1000000 + 10#$fp )); }

_usd() { local m=${1:-0}
  if [ "$m" -ge 100000000 ]; then printf -v RET '$%d' $(( m / 1000000 ))
  else printf -v RET '$%d.%02d' $(( m / 1000000 )) $(( (m % 1000000) / 10000 )); fi; }

# ── monthly ledger + work-day pacing (only with a configured budget; feeds
# the Enterprise-seat month meter, which has no window the harness reports) ──
MO_PCT=""; MO_MTD=""
if [ -n "$MONTHLY_LIMIT_USD" ] && [ -n "$SESSION" ] && [ -n "$COST" ]; then
  LG="$HOME/.claude/.statusline-ledger"
  _lmonth=""; _ltotal=0; _lday=""; _ldaytot=0; _mine=0; _keep=""
  if [ -f "$LG" ]; then
    while read -r k a b c; do
      case "$k" in
        month) _lmonth="$a" ;;
        total) _ltotal="$a" ;;
        day)   _lday="$a"; _ldaytot="$b" ;;
        # per-session cumulative baseline, so a delta is only ever counted once.
        # Baselines survive a month rollover on purpose: a session running across
        # midnight on the 1st must contribute only its post-rollover spend, not
        # its whole cumulative cost.
        # A row whose figures are not figures is a corrupt line, not a session:
        # feeding it to the arithmetic below prints an error on every redraw and
        # then loses the whole month's ledger. Drop it instead.
        s) if [ -z "${b//[0-9]/}" ] && [ -n "$b" ] && [ -z "${c//[0-9]/}" ]; then
             if [ "$a" = "$SESSION" ]; then _mine="$b"
             elif [ $(( NOW - ${c:-0} )) -lt 3024000 ]; then
               _keep+="s $a $b ${c:-$NOW}"$'\n'
             fi
           fi ;;
      esac
    done < "$LG"
  fi
  if [ "$_lmonth" != "$MONTH" ]; then _ltotal=0; fi
  if [ "$_lday" != "$TODAY" ]; then _ldaytot=0; fi

  _micro "$COST"; _now_micro=$RET
  _delta=$(( _now_micro - _mine ))
  # A session's cumulative cost must never appear to go backwards. A resume or a
  # replayed payload can report less than we last saw; clamping the delta is not
  # enough, because storing the lower figure would make the next render re-add
  # the whole difference. Keep the baseline monotonic.
  if [ "$_delta" -lt 0 ]; then _delta=0; _now_micro=$_mine; fi
  _ltotal=$(( _ltotal + _delta ))
  _ldaytot=$(( _ldaytot + _delta ))
  printf 'month %s\ntotal %s\nday %s %s\n%ss %s %s %s\n' \
    "$MONTH" "$_ltotal" "$TODAY" "$_ldaytot" "$_keep" "$SESSION" "$_now_micro" "$NOW" > "$LG.$$" 2>/dev/null &&
    mv -f "$LG.$$" "$LG" 2>/dev/null

  _micro "$MONTHLY_LIMIT_USD"; _lim=$RET
  if [ "$_lim" -gt 0 ]; then
    MO_PCT=$(( _ltotal * 100 / _lim ))
    _usd "$_ltotal"; MO_MTD=$RET

    # days in this month, no forks
    case $MON in
      1|3|5|7|8|10|12) _dim=31 ;;
      4|6|9|11)        _dim=30 ;;
      2) if { [ $(( YEAR % 4 )) -eq 0 ] && [ $(( YEAR % 100 )) -ne 0 ]; } || [ $(( YEAR % 400 )) -eq 0 ]
         then _dim=29; else _dim=28; fi ;;
      *) _dim=30 ;;
    esac
    # walk the month deriving each day's weekday from today's, and count the
    # ones the budget is spread across
    _wd_total=0; _wd_done=0; _d=1
    while [ "$_d" -le "$_dim" ]; do
      _dw=$(( ( (DOW - 1 - (DOM - _d)) % 7 + 7 ) % 7 + 1 ))
      if [ "$WORKDAYS" = all ] || [ "$_dw" -le 5 ]; then
        _wd_total=$(( _wd_total + 1 ))
        [ "$_d" -le "$DOM" ] && _wd_done=$(( _wd_done + 1 ))
      fi
      _d=$(( _d + 1 ))
    done
    # a weekend today still spends the budget, so give it a day's share to sit in
    [ "$_wd_done" -eq 0 ] && _wd_done=1
    if [ "$_wd_total" -gt 0 ]; then
      # everything the enterprise-seat month meter needs, in micro-dollars
      BUD_LIM=$_lim; BUD_MTD=$_ltotal
      BUD_WDT=$_wd_total; BUD_WDD=$_wd_done
    fi
  fi
fi
# ── worktree: walk up for .git, no fork ──────────────────────────────────────
# A linked worktree has .git as a *file* holding "gitdir: …/worktrees/<name>".
GITDIR=""; WT_LABEL="$WT_NAME"
_d="$CWD"
while [ -n "$_d" ] && [ "$_d" != "/" ]; do
  if [ -d "$_d/.git" ]; then GITDIR="$_d/.git"; break
  elif [ -f "$_d/.git" ]; then
    read -r _k _v < "$_d/.git"
    if [ "$_k" = "gitdir:" ]; then
      GITDIR="$_v"
      case "$_v" in */worktrees/*) [ -z "$WT_LABEL" ] && WT_LABEL="${_d##*/}" ;; esac
    fi
    break
  fi
  _d="${_d%/*}"
done

# ── git: one spawn — branch, upstream divergence, file counts ────────────────
BRANCH=""; GIT_ST_RAW=""; GIT_DIV=""; GIT_OP=""
if [ -n "$GITDIR" ]; then
  st=0; un=0; qu=0; cf=0
  while IFS= read -r line; do
    case "$line" in
      '## '*)
        hdr="${line#\#\# }"
        case "$hdr" in
          'HEAD (no branch)')
            if read -r _h < "$GITDIR/HEAD" 2>/dev/null; then BRANCH="${_h:0:7}"; else BRANCH="detached"; fi
            GIT_DIV="${GRY}detached${R}" ;;
          'No commits yet on '*) BRANCH="${hdr#No commits yet on }"; GIT_DIV="${GRY}new${R}" ;;
          *)
            ab=""
            case "$hdr" in *' ['*) ab="${hdr##*[}"; ab="${ab%]}"; hdr="${hdr%% [*}" ;; esac
            up=""
            case "$hdr" in *...*) up="${hdr##*...}"; BRANCH="${hdr%%...*}" ;; *) BRANCH="$hdr" ;; esac
            if [ -z "$up" ]; then GIT_DIV="${GRY}${I_NOUP}${R}"
            else
              case "$ab" in *'ahead '*) a="${ab##*ahead }"; a="${a%%,*}"; GIT_DIV+="${CYN}↑${a}${R}" ;; esac
              case "$ab" in *'behind '*) b="${ab##*behind }"; b="${b%%,*}"; GIT_DIV+="${MAG}↓${b}${R}" ;; esac
            fi ;;
        esac ;;
      '??'*) qu=$(( qu + 1 )) ;;
      *) x="${line:0:1}"; y="${line:1:1}"
         # An unmerged path is a conflict, not "staged and unstaged at once" —
         # counting UU as both was wrong and hid the only state that blocks you.
         case "$x$y" in
           DD|AU|UD|UA|DU|AA|UU) cf=$(( cf + 1 )) ;;
           *) [ -n "$x" ] && [ "$x" != ' ' ] && st=$(( st + 1 ))
              [ -n "$y" ] && [ "$y" != ' ' ] && un=$(( un + 1 )) ;;
         esac ;;
    esac
  done < <(git -C "$CWD" --no-optional-locks status --porcelain=v1 --branch --untracked-files=normal 2>/dev/null)
  # A clean tree needs no mark of its own - the branch simply stays green.
  [ "$cf" -gt 0 ] && GIT_ST_RAW+="${RED}!${cf}${R}"
  [ "$st" -gt 0 ] && GIT_ST_RAW+="${GRN}+${st}${R}"
  [ "$un" -gt 0 ] && GIT_ST_RAW+="${YEL}~${un}${R}"
  [ "$qu" -gt 0 ] && GIT_ST_RAW+="${GRY}?${qu}${R}"

  # In-progress operation, read straight out of the git dir (no extra spawn).
  # During a rebase, "detached at 150eba2" is useless — the branch being
  # rebased and how far along it is are what you actually need.
  OP=""; OP_BR=""
  if [ -d "$GITDIR/rebase-merge" ]; then
    read -r _hn < "$GITDIR/rebase-merge/head-name" 2>/dev/null
    read -r _n  < "$GITDIR/rebase-merge/msgnum"    2>/dev/null
    read -r _e  < "$GITDIR/rebase-merge/end"       2>/dev/null
    OP_BR="${_hn#refs/heads/}"; OP="REBASE"
    [ -n "$_n" ] && [ -n "$_e" ] && OP="REBASE ${_n}/${_e}"
  elif [ -d "$GITDIR/rebase-apply" ]; then
    read -r _hn < "$GITDIR/rebase-apply/head-name" 2>/dev/null
    read -r _n  < "$GITDIR/rebase-apply/next"      2>/dev/null
    read -r _e  < "$GITDIR/rebase-apply/last"      2>/dev/null
    OP_BR="${_hn#refs/heads/}"
    if [ -f "$GITDIR/rebase-apply/applying" ]; then OP="AM"; else OP="REBASE"; fi
    [ -n "$_n" ] && [ -n "$_e" ] && OP="${OP} ${_n}/${_e}"
  elif [ -f "$GITDIR/MERGE_HEAD" ];       then OP="MERGE"
  elif [ -f "$GITDIR/CHERRY_PICK_HEAD" ]; then OP="CHERRY-PICK"
  elif [ -f "$GITDIR/REVERT_HEAD" ];      then OP="REVERT"
  elif [ -f "$GITDIR/BISECT_LOG" ];       then OP="BISECT"
  fi
  if [ -n "$OP" ]; then
    [ -n "$OP_BR" ] && BRANCH="$OP_BR" && GIT_DIV=""
    GIT_OP="${ORG}⇋ ${OP}${R}"
  fi
fi

# One meter, shared by _usage_meters. BARS=blocks gives the ▓░ gauge; BARS=rule
# gives a thin ━ rule with a dim remainder and a right-aligned
# percentage, so the whole tail fits on one line.
# A meter with nothing behind it yet: dim track, an em dash instead of a
# fabricated 0%, and the reason. Used on a fresh session, before the first
# API response has reported any window.
_meter_na() { local lbl=$1 note=$2 w i track=""
  if [ "$BARS" = rule ]; then w=$RULE_W; else w=$BAR_WIDTH; fi
  for ((i=0;i<w;i++)); do
    if [ "$BARS" = rule ]; then track+="━"; else track+="░"; fi
  done
  printf -v RET '%s%s%s %s%s%s %s%s%s%s' \
    "$GRY" "$lbl" "$R" "${D}${GRY}" "$track" "$R" \
    "$GRY" "  --" "$R" "${note:+ ${D}${GRY}${note}${R}}"; }

_meter() { local lbl=$1 p=$2 c=$3 suf=$4 mk=$5 w i fill="" rest=""
  if [ "$BARS" = rule ]; then
    w=$RULE_W
    i=$(( p * w / 100 )); [ "$i" -gt "$w" ] && i=$w; [ "$i" -lt 0 ] && i=0
    while [ "$i" -gt 0 ]; do fill+="━"; i=$(( i - 1 )); done
    i=$(( w - ${#fill} ))
    while [ "$i" -gt 0 ]; do rest+="━"; i=$(( i - 1 )); done
    printf -v RET '%s%s%s %s%s%s%s%s %s%3s%%%s%s%s' \
      "$GRY" "$lbl" "$R" "$c" "$fill" "${D}${GRY}" "$rest" "$R" \
      "$c" "$p" "$R" "${mk:+${D}${GRY}${mk}${R}}" "${suf:+ ${GRY}${suf}${R}}"
  else
    _bar "$p" "$BAR_WIDTH"
    printf -v RET '%s%s%s %s%s%s %s%s%%%s%s%s' \
      "$GRY" "$lbl" "$R" "$c" "$RET" "$R" "$c" "$p" "$R" \
      "${mk:+${D}${GRY}${mk}${R}}" "${suf:+ ${GRY}${suf}${R}}"
  fi; }

# The context segment: colour steps via
# CTX_STEPS, an optional inline bar (CTX_BAR_W), and a filled red chip once
# usage clears the top step - the one meter where "past red" still needs room
# to escalate further. Sets RET to the whole "ctx <bar> NN%" segment.
_ctx_seg() { local p=${1:-0} cc bg="" w=${CTX_BAR_W:-0} f m n i fill="" rest="" cb=""
  if   [ "$p" -ge "$C_R" ]; then cc=$RED; bg=1
  elif [ "$p" -ge "$C_O" ]; then cc=$RED
  elif [ "$p" -ge "$C_Y" ]; then cc=$YEL
  else cc=$GRN; fi
  if [ "$w" -gt 0 ] 2>/dev/null; then
    if [ "$BARS" = rule ]; then f="━"; m="━"; else f="▓"; m="░"; fi
    n=$(( (p * w + 50) / 100 )); [ "$n" -gt "$w" ] && n=$w; [ "$n" -lt 0 ] && n=0
    for ((i=0;i<n;i++)); do fill+=$f; done
    for ((i=n;i<w;i++)); do rest+=$m; done
    if [ -n "$bg" ]; then cb=" ${fill}${rest}"
    else cb=" ${cc}${fill}${R}${D}${GRY}${rest}${R}"; fi
  fi
  if [ -n "$bg" ]; then RET="${B}${BG_RED}${INK_ON} ctx${cb} ${p}% ${R}"
  else RET="${cc}ctx${R}${cb} ${cc}${p}%${R}"; fi; }

# Team-seat 5h+week meters with the weekly burn-rate projection, or the
# Enterprise month-budget meter when there's no window the harness reports for
# that seat. Sets RET. Needs WK_ANC / WK_APCT and the FH_MK / WK_MK reset marks
# from the usage-window-anchor block, so callers must run after it.
_usage_meters() { local seg="" lim msuf proj s wksuf wkst wkel wkrem wkg wkpr pc
  if [ "$SL_SEAT" = enterprise ] && [ -n "${BUD_LIM:-}" ]; then
    _usd "$BUD_LIM"; lim=$RET
    msuf="${GRY}of ${lim}${R}"
    proj=$(( BUD_MTD * BUD_WDT / BUD_WDD ))
    if [ "$proj" -gt "$BUD_LIM" ]; then
      _usd "$proj"; msuf+=" ${ORG}→ ${RET}${R}"
    fi
    _meter "${I_MO}${L_MO}" "$MO_PCT" "$MO_C" "$msuf"; seg="$RET"
  else
    if [ -n "$FH_PCT" ]; then
      _until "$FH_RST"; s=$RET
      _meter "$M_5H" "$FH_PCT" "$FH_C" "$s" "$FH_MK"; seg="$RET"
    else
      _meter_na "$M_5H" "not reported yet"; seg="$RET"
    fi
    if [ -n "$WK_PCT" ]; then
      _until "$WK_RST"; wksuf=$RET
      if [ "$SHOW_WK_PACE" = on ] && [ "$WK_PCT" -gt 0 ] \
         && [ "${WK_RST:-x}" -gt 0 ] 2>/dev/null; then
        wkst=${WK_ANC:-$(( WK_RST - 604800 ))}
        if [ "$NOW" -gt "$wkst" ] && [ "$NOW" -lt "$WK_RST" ]; then
          _worked "$wkst" "$NOW"; wkel=$RET
          _worked "$NOW" "$WK_RST"; wkrem=$RET
          if [ "$wkel" -ge 21600 ]; then
            wkg=$(( WK_PCT - WK_APCT )); [ "$wkg" -lt 0 ] && wkg=0
            wkpr=$(( WK_PCT + wkg * wkrem / wkel ))
            pc=""
            if [ "$wkpr" -gt "$W_O" ]; then
              [ "$wkpr" -gt 999 ] && wkpr=999
              pc=$ORG; { [ "$wkpr" -ge "$W_H" ] || [ "$WK_C" = "$RED" ]; } && pc=$RED
            elif [ "$wkpr" -le "$W_U" ]; then pc=$GRN
            fi
            [ -n "$pc" ] && wksuf+=" ${pc}→ ${wkpr}%${R}"
          fi
        fi
      fi
      _meter "$M_WK" "$WK_PCT" "$WK_C" "$wksuf" "$WK_MK"; seg="${seg}   $RET"
    else
      _meter_na "$M_WK" ""; seg="${seg}   $RET"
    fi
  fi
  RET="$seg"; }

# ── model tier chip ──────────────────────────────────────────────────────────
# The model is easy to be on without meaning to be, and the line otherwise
# prints it in the same quiet colour as the rest of the line. So every tier
# gets its own filled chip: Haiku grey, Sonnet green, Opus yellow, Fable red.
_MTIER=""
if [ "$HILITE_MODEL" = on ]; then
  case "$MODEL_ID $MODEL" in
    *[Ff]able*)  _MTIER=fable ;;
    *[Oo]pus*)   _MTIER=opus ;;
    *[Ss]onnet*) _MTIER=sonnet ;;
    *[Hh]aiku*)  _MTIER=haiku ;;
  esac
fi
# $1 the text, $2 the colour it wears when the tier is unknown
_mstyle() { case "$_MTIER" in
    fable)  RET="${B}${BG_RED}${INK_ON} $1 ${R}" ;;
    opus)   RET="${B}${BG_YEL}${INK_ON} $1 ${R}" ;;
    sonnet) RET="${B}${BG_GRN}${INK_ON} $1 ${R}" ;;
    haiku)  RET="${B}${BG_GRY}${INK_ON} $1 ${R}" ;;
    *)      RET="$2$1${R}" ;;
  esac; }

CTXPCT=${CTXPCT:-0}
_color_ctx "$CTXPCT";  CTX_C=$RET
_color "${FH_PCT:-0}"; FH_C=$RET
_color "${WK_PCT:-0}"; WK_C=$RET
MO_C=""
[ -n "$MO_PCT" ] && { _color "$MO_PCT"; MO_C=$RET; }

# ── usage window anchors ─────────────────────────────────────────────────────
# Anthropic occasionally zeroes a window's usage part-way through without moving
# its reset - a support adjustment, seen a few times a year on Team seats. The
# harness passes the server's figure straight through, so the gauges drop to 0%
# and count up again under the old reset time. The weekly projection assumed
# the window began seven days before that reset, so after such a reset it
# divided a small fresh usage by a large elapsed time and read as calm.
#
# Each window's high-water mark is kept in a one-line state file. A reading
# that falls a reset's worth below the mark moves the projection's anchor to
# now. A stale session that still reports the pre-reset figure lifts the mark
# again; a fresh reading that sits on the anchored trajectory then just lowers
# the mark, so the anchor does not slide. One read per redraw, a write only
# when something changed.
WIN_F="$HOME/.claude/.statusline-windows"
WK_ANC=""; WK_APCT=0
A_ANC=""; A_APCT=0; A_HWM=0; A_CHG=""
_win_anchor() { # _win_anchor <rst> <pct> <len> <s_rst> <s_anc> <s_apct> <s_hwm>
  local rst=$1 pct=$2 len=$3 s_rst=$4 s_anc=$5 s_apct=$6 s_hwm=$7 nom
  nom=$(( rst - len )); A_CHG=""
  if [ "$s_rst" != "$rst" ] || ! [ "$s_anc" -ge 0 ] 2>/dev/null \
     || ! [ "$s_apct" -ge 0 ] 2>/dev/null || ! [ "$s_hwm" -ge 0 ] 2>/dev/null; then
    A_ANC=$nom; A_APCT=0; A_HWM=$pct; A_CHG=1; return        # a new window
  fi
  if [ $(( pct + 5 )) -le "$s_hwm" ] && [ $(( pct * 2 )) -le "$s_hwm" ]; then
    if [ "$s_anc" -gt "$nom" ] && [ "$pct" -ge "$s_apct" ]; then
      A_ANC=$s_anc; A_APCT=$s_apct; A_HWM=$pct; A_CHG=1     # stale mark, same anchor
    else
      A_ANC=$NOW; A_APCT=$pct; A_HWM=$pct; A_CHG=1           # usage was reset
    fi; return
  fi
  A_ANC=$s_anc; A_APCT=$s_apct; A_HWM=$s_hwm
  [ "$pct" -gt "$s_hwm" ] && { A_HWM=$pct; A_CHG=1; }; }

_wr=""; _wa=""; _wp=""; _wh=""; _fr=""; _fa=""; _fp=""; _fh=""; _wchg=""
[ -f "$WIN_F" ] && read -r _wr _wa _wp _wh _fr _fa _fp _fh < "$WIN_F" 2>/dev/null
if [ -n "$WK_PCT" ] && [ "${WK_RST:-0}" -gt 0 ] 2>/dev/null; then
  _win_anchor "$WK_RST" "$WK_PCT" 604800 "$_wr" "$_wa" "$_wp" "$_wh"
  _wr=$WK_RST; _wa=$A_ANC; _wp=$A_APCT; _wh=$A_HWM; [ -n "$A_CHG" ] && _wchg=1
  WK_ANC=$_wa; WK_APCT=$_wp
fi
if [ -n "$FH_PCT" ] && [ "${FH_RST:-0}" -gt 0 ] 2>/dev/null; then
  _win_anchor "$FH_RST" "$FH_PCT" 18000 "$_fr" "$_fa" "$_fp" "$_fh"
  _fr=$FH_RST; _fa=$A_ANC; _fp=$A_APCT; _fh=$A_HWM; [ -n "$A_CHG" ] && _wchg=1
fi
[ -n "$_wchg" ] && printf '%s %s %s %s %s %s %s %s\n' \
  "${_wr:-0}" "${_wa:-0}" "${_wp:-0}" "${_wh:-0}" \
  "${_fr:-0}" "${_fa:-0}" "${_fp:-0}" "${_fh:-0}" > "$WIN_F" 2>/dev/null

# A window whose anchor sits past its nominal start was reset mid-window, and
# carries a dim mark for the rest of that window - otherwise the drop reads as
# a sudden idle stretch rather than the adjustment it was.
FH_MK=""; WK_MK=""
[ -n "$WK_PCT" ] && [ "${WK_RST:-0}" -gt 0 ] 2>/dev/null \
  && [ "${WK_ANC:-0}" -gt $(( WK_RST - 604800 )) ] 2>/dev/null && WK_MK=$I_RST
[ -n "$FH_PCT" ] && [ "${FH_RST:-0}" -gt 0 ] 2>/dev/null \
  && [ "${_fa:-0}" -gt $(( FH_RST - 18000 )) ] 2>/dev/null && FH_MK=$I_RST

# separator glyph
case "$SEP" in
  dot)   _sep=" ${D}${GRY}·${R} " ;;
  space) _sep="   " ;;
  *)     _sep=" ${D}${GRY}│${R} " ;;
esac
# The branch is introduced by the glyph set's branch mark rather than the
# ordinary separator, so the ref reads as a branch at a glance.
_bsep=" ${D}${GRY}${I_BR}${R} "

# ── GitHub, then Claude Code, then alerts only when they need you ──────────
# Line 1 (GitHub): repo [wt] ⎇ branch │ JIRA-KEY status │ PR │ model effort —
# quiet chips, what's true right now, not what needs you.
# Line 2 (Claude Code): [agent] │ ctx │ usage meters (5h + week bars on a
# Team seat, the month budget bar on Enterprise).
# Line 3 (alerts) appears only when something is actionable, in a fixed
# order: PR changes requested, plugin drift. Remote segments read a local
# cache under ~/.claude/.statusline-cache and kick off a detached refresh when
# stale, so a redraw never waits on the network.
{
  # cache: file = "<expires>\n<field US field ...>". RET holds the fields, or is
  # empty when absent. A stale entry is still served while a refresh runs.
  _cache() { local name=$1 exp="" body=""
    RET=""; CACHE_STALE=1
    [ -f "$SL_CACHE/$name" ] || return
    { read -r exp; IFS= read -r body; } < "$SL_CACHE/$name"
    RET=$body
    [ -n "$exp" ] && [ "$exp" -gt "$NOW" ] 2>/dev/null && CACHE_STALE=""; }
  _refresh() { # _refresh <segment> [args...]  - detached, never awaited
    [ -f "$SL_REFRESH" ] || return
    command -v python3 >/dev/null 2>&1 || return
    local lock="$SL_CACHE/$1.lock"
    if [ -f "$lock" ]; then
      read -r _lt < "$lock"; [ $(( NOW - ${_lt:-0} )) -lt 90 ] && return
    fi
    mkdir -p "$SL_CACHE" 2>/dev/null
    printf '%s\n' "$NOW" > "$lock" 2>/dev/null
    ( nohup python3 "$SL_REFRESH" "$@" >/dev/null 2>&1 </dev/null & ) 2>/dev/null; }

  # ── line 1: GitHub — branch, ticket, PR. Quiet chips: what's true right now,
  # not what needs you. A request for changes still wears its colour here, but
  # the same fact also earns a spot on line 3 below, since that is the one
  # that actually needs you to act. ──
  # Just the folder you're actually in - not the whole chain back to the
  # project root, which reads as noise once you're a few levels deep.
  _folder="${CWD##*/}"
  _path_link "$CWD" "${BLU}${_folder}${R}"; L1=$RET
  [ -n "$WT_LABEL" ] && L1+=" ${D}${GRY}${I_WT}${R} ${BLU}${WT_LABEL}${R}"
  if [ -n "$BRANCH" ]; then
    if [ -z "$GIT_ST_RAW" ] && [ -z "$GIT_OP" ]; then
      L1+="${L1:+$_bsep}${GRN}${BRANCH}${R}${GIT_DIV:+ $GIT_DIV}"
    else
      L1+="${L1:+$_bsep}${ORG}${BRANCH}${R}${GIT_ST_RAW:+ $GIT_ST_RAW}${GIT_DIV:+ $GIT_DIV}${GIT_OP:+ $GIT_OP}"
    fi
  fi
  # Jira key anywhere in the ref: feature/PROJ-123/x and feature-PROJ-123-x both
  JKEY=""
  if [ "$SHOW_JIRA" = on ] && [[ "$BRANCH" =~ ([A-Z][A-Z0-9]{1,9}-[0-9]+) ]]; then
    JKEY=${BASH_REMATCH[1]}
    if [ -n "$JIRA_SITE" ]; then
      _link "${JIRA_SITE%/}/browse/${JKEY}" "${B}${MAG}${JKEY}${R}"; _jseg=$RET
    else
      _jseg="${B}${MAG}${JKEY}${R}"
    fi
    _cache "jira-$JKEY"; _jf=$RET
    if [ -n "$_jf" ]; then
      IFS="$US" read -r _jstatus _ <<< "$_jf"   # summary/assignee cached, unused
      [ -n "$_jstatus" ] && _jseg+=" ${GRY}${_jstatus}${R}"
    fi
    [ -n "$JIRA_SITE" ] && [ -n "$CACHE_STALE" ] && _refresh jira "$JKEY" "$JIRA_SITE"
    L1+="${L1:+$_sep}${_jseg}"
  fi
  # PR: the quiet status. Only "changes requested" wears red here too, so a
  # glance still tells it apart from "review" or "pending".
  if [ "$SHOW_PR" = on ] && [ -n "$PR_NUM" ]; then
    _link "$PR_URL" "${I_PR} #${PR_NUM}"; _prl=$RET
    case "$PR_STATE" in
      APPROVED|approved) L1+="${L1:+$_sep}${GRY}${_prl} approved${R}" ;;
      CHANGES_REQUESTED|changes_requested) L1+="${L1:+$_sep}${GRY}${_prl}${R} ${RED}changes requested${R}" ;;
      "") L1+="${L1:+$_sep}${GRY}${_prl}${R}" ;;
      *) _ps=$(printf '%s' "$PR_STATE" | tr '[:upper:]' '[:lower:]'); _ps=${_ps//_/ }
         L1+="${L1:+$_sep}${GRY}${_prl} ${_ps}${R}" ;;
    esac
  fi
  # Model and effort ride at the end of this row, not the head of the next:
  # where you are comes first, and which model is answering is the last thing
  # you read before the meters below. Fast mode stays with the model it marks.
  _mid="${MODEL_ID#claude-}"; [ -z "$_mid" ] && _mid="$MODEL"
  case "$EFFORT" in
    low|medium|high|xhigh|max) _eff=$EFFORT ;; *) _eff="" ;;
  esac
  _mstyle "$_mid" "$GRY"
  L1+="${L1:+$_sep}${RET}${_eff:+ ${B}${GRY}${_eff}${R}}"
  [ -n "$FAST" ] && L1+=" ${YEL}${I_FAST}${R}"

  # ── line 2: Claude Code — context and what you have spent ──
  L2=""
  [ -n "$AGENT" ] && L2+="${GRY}agent${R} ${BLU}${AGENT}${R}"
  _ctx_seg "$CTXPCT"; L2+="${L2:+$_sep}${RET}"
  _usage_meters; L2+="${_sep}${RET}"

  # ── line 3: alerts — only what needs a decision from you, fixed order ──
  L3=""
  _add() { L3+="${L3:+$_sep}$1"; }

  # PR: line 1 already shows the quiet status chip. The only state that
  # actually needs you back in the PR is a request for changes.
  if [ "$SHOW_PR" = on ] && [ -n "$PR_NUM" ]; then
    case "$PR_STATE" in
      CHANGES_REQUESTED|changes_requested)
        _link "$PR_URL" "#${PR_NUM}"; _add "${RED}PR ${RET} changes requested${R}" ;;
    esac
  fi

  # a watched plugin behind its marketplace; silent until WATCH_PLUGIN names one
  if [ "$SHOW_DRIFT" = on ] && [ -n "$WATCH_PLUGIN" ]; then
    _cache drift; _df=$RET
    [ -n "$CACHE_STALE" ] && _refresh drift "$WATCH_PLUGIN"
    if [ -n "$_df" ]; then
      IFS="$US" read -r _dbehind _dname <<< "$_df"
      if [ "${_dbehind:-0}" -gt 0 ] 2>/dev/null; then
        _add "${GRY}${_dname:-plugin} plugin${R} ${ORG}${_dbehind} behind${R} ${GRY}/plugin update ${_dname:-plugin}${R}"
      fi
    fi
  fi

  _out=("$L1" "$L2"); [ -n "$L3" ] && _out+=("$L3")
  printf '%s\n' "${_out[@]}"
}
