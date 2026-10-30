#!/usr/bin/env zsh
# claude-code-statusline: a two-row status line for Claude Code.
# Dracula colours, gradient usage bars with a pace marker, an account chip, and the PR (or,
# if you opt in, the ticket) you are working on, read from your branch and folder names.
# Requires: zsh, jq. Optional: gh (PR titles), a Nerd Font (rounded account chip).
#
#   Work │ ◆ Opus 5.5 · high │ Acme-Shop │ #42 Coupon applies twice │ Checkout refactor
#   ctx ━━━━━━━━━━ 65% │ 5h ━━━━│━━━━━ 74% ↻ 2h52m │ 7d ━━━━━━━│━━ 30% │ $3.12
#
# Row 1: account chip (the login Claude Code is using, from .claude.json; SHOW_ACCOUNT=0
#   hides it), model · effort, project folder (· git branch), the ticket or PR you are on,
#   then the session name, which is shortened or dropped first when the pane is narrow.
# Row 2: context, 5-hour and 7-day limits, session cost. Bar cells are heavy-line glyphs,
#   centred on the text in every terminal. Filled cells run green > yellow > orange > red;
#   the percent is green below 50%, yellow to 79%, red from 80%.
#   The pink │ on 5h and 7d is pace: how much of that window has passed. Fill ahead of it
#   means you are spending faster than the window refills. The reset time shows only on a
#   limit at 70% or more. "ctx 1M" names a context window that is not 200k.
#
# Settings: ${CLAUDE_STATUSLINE_CONF:-~/.config/claude-statusline/config.zsh}, see
# config.example.zsh. Everything works without it.
#
# Bar, pace marker and palette are adapted from briansmith80/claude-code-status-bar (MIT);
# see THIRD-PARTY.md.

export LC_ALL=en_US.UTF-8
setopt extendedglob
zmodload -F zsh/stat b:zstat 2>/dev/null

# --- Settings (override in the config file) ---
SHOW_ACCOUNT=1                    # 0 = no account chip (and .claude.json is never read)
ACCOUNTS=()                       # "email|Label|bg r;g;b|fg r;g;b", one entry per login
PILL=0                            # 1 = rounded chip ends (needs a Nerd Font)
TICKET_PATTERN=''                 # regex; match[1] = the ticket folder name. '' = off
TICKET_MAX=40                     # longest ticket title shown
PR_TITLES=1                       # 0 = never call gh
CONF="${CLAUDE_STATUSLINE_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-statusline/config.zsh}"
# Loaded only if it is yours and not world-writable: it runs as zsh code.
[[ -r "$CONF" && -O "$CONF" ]] && (( ($(zstat +mode "$CONF" 2>/dev/null || print 2) & 8#002) == 0 )) && source "$CONF"

rgb() { printf '\033[38;2;%s;%s;%sm' "$1" "$2" "$3"; }
RESET=$'\033[0m'
BOLD=$'\033[1m'
# Dracula
TEXT="$(rgb 248 248 242)"
MUTED="$(rgb 98 114 164)"
PURPLE="$(rgb 189 147 249)"
PINK="$(rgb 255 121 198)"
CYAN="$(rgb 139 233 253)"
ORANGE="$(rgb 255 184 108)"
GREEN="$(rgb 80 250 123)"
YELLOW="$(rgb 241 250 140)"
RED="$(rgb 255 85 85)"
# Bar cells, left to right: dracula green, yellow, orange, red, each mixed 15% toward the
# dracula background (40 42 54) so full blocks don't glare.
RAMP=(74 219 113  211 219 127  223 163 100  223 79 80)
# The empty part of a bar: the same block in dracula "current line" grey.
TRACK="$(rgb 68 71 90)"
SEP=" ${MUTED}│${RESET} "
SEP_W=3

command -v jq >/dev/null 2>&1 || { echo "statusline: jq not found"; exit 0; }

[[ -t 0 ]] || input_json="$(cat 2>/dev/null)"
[[ -z "$input_json" ]] && input_json='{}'

# One jq call; fields joined by U+001F so empty values survive `read`.
IFS=$'\x1f' read -r MODEL EFFORT SESSION DIR PROJ CTX CTX_SIZE BIG R5 R5_AT R7 R7_AT COST \
  STYLE VIM AGENT PR_NUM PR_STATE <<<"$(jq -r '[
  (.model.display_name // ""),
  (.effort.level // ""),
  (.session_name // ""),
  (.workspace.current_dir // .cwd // ""),
  (.workspace.project_dir // ""),
  (.context_window.used_percentage // ""),
  (.context_window.context_window_size // ""),
  (.exceeds_200k_tokens // false),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.five_hour.resets_at // ""),
  (.rate_limits.seven_day.used_percentage // ""),
  (.rate_limits.seven_day.resets_at // ""),
  (.cost.total_cost_usd // ""),
  (.output_style.name // ""),
  (.vim.mode // ""),
  (.agent.name // ""),
  (.pr.number // ""),
  (.pr.review_state // "")
] | map(tostring) | join("\u001f")' <<<"$input_json" 2>/dev/null)"

# Names are printed to the terminal: drop control characters so a folder, model or ticket
# name carrying escape codes shows as text instead of retitling or clearing the window.
# DIR and PROJ stay as they are for git and the file tests; only what is shown is cleaned.
for v in MODEL EFFORT SESSION STYLE VIM AGENT PR_STATE; do : ${(P)v::=${(P)v//[[:cntrl:]]/}}; done
# A PR number is digits or nothing: it is passed to gh and must never read as an option.
[[ "$PR_NUM" == <-> ]] || PR_NUM=""

to_int() { local n="${1%%.*}"; [[ "$n" =~ ^[0-9]+$ ]] && printf '%s' "$n" || printf 0; }

# Percent colour: green below 50%, yellow to 79%, red from 80%.
level_c() {
  if   (($1 >= 80)); then print -r -- "$RED"
  elif (($1 >= 50)); then print -r -- "$YELLOW"
  else                    print -r -- "$GREEN"; fi
}

# Bar: BAR_W cells. Filled cells take their colour from their place on the ramp, empty
# cells are a dim track, and $2 (0-100, optional) puts a pink │ pace marker in its cell.
BAR_W=10
bar() {
  local pct w=$BAR_W filled mark=-1 i pos seg frac r g b out="" c
  pct="$(to_int "$1")"
  ((pct > 100)) && pct=100
  filled=$((pct * w / 100))
  if [[ -n "$2" ]]; then mark=$(($2 * w / 100)); ((mark >= w)) && mark=$((w - 1)); fi
  for ((i = 0; i < w; i++)); do
    if ((i == mark)); then out+="${PINK}│"
    elif ((i < filled)); then
      pos=$((i * 3000 / (w - 1))) seg=$((pos / 1000)) frac=$((pos % 1000))
      ((seg >= 3)) && seg=2 frac=1000
      c=(${RAMP[@]:$((seg * 3)):6})
      r=$((c[1] + (c[4] - c[1]) * frac / 1000))
      g=$((c[2] + (c[5] - c[2]) * frac / 1000))
      b=$((c[3] + (c[6] - c[3]) * frac / 1000))
      out+="$(rgb $r $g $b)━"
    else out+="${TRACK}━"; fi
  done
  printf '%s' "${out}${RESET} $(level_c $pct)${pct}%${RESET}"
}

# Pace: percent of the limit window already passed. $1 resets_at, $2 window seconds.
pace() {
  local at="$(to_int "$1")" el
  ((at == 0)) && return
  el=$(($(date +%s) - (at - $2)))
  ((el < 0)) && el=0; ((el > $2)) && el=$2
  print $(((el * 100 + $2 / 2) / $2))
}

# Time until reset: 45m / 2h45m / 1d13h. Nothing once it has passed.
reset_in() {
  local at="$(to_int "$1")" diff m
  ((at == 0)) && return
  diff=$((at - $(date +%s)))
  ((diff <= 0)) && return
  m=$(((diff + 59) / 60))
  if ((m < 60)); then printf '%dm' $m
  elif ((m < 1440)); then printf '%dh%02dm' $((m / 60)) $((m % 60))
  else printf '%dd%dh' $((m / 1440)) $((m % 1440 / 60)); fi
}

# Width: Claude Code passes the pane width in COLUMNS. Keep 2 spare so the last cell never wraps.
# Without a real width (zsh may set COLUMNS to 0 with no terminal), assume 120.
MAXW=$(to_int "$COLUMNS")
((MAXW < 20)) && MAXW=120
MAXW=$((MAXW - 2))
((MAXW < 40)) && MAXW=40

# Visible width of a coloured string (escape codes stripped).
vis_width() { local t="${1//$'\e'\[[0-9;]#m/}"; print -r -- ${(m)#t}; }

# Print the parts joined by SEP, starting a new line when the next part would not fit.
emit() {
  local line="" lw=0 part w
  for part in "$@"; do
    w=$(vis_width "$part")
    if [[ -z "$line" ]]; then line="$part" lw=$w
    elif ((lw + SEP_W + w <= MAXW)); then line+="${SEP}${part}" lw=$((lw + SEP_W + w))
    else printf '%s\n' "$line"; line="$part" lw=$w; fi
  done
  [[ -n "$line" ]] && printf '%s\n' "$line"
}

# Token count: 950 / 45.2k / 120k / 1.3M (no trailing .0).
tokens() {
  local t="$(to_int "$1")" out
  if ((t >= 1000000)); then out="$(printf '%.1fM' $((t / 1000000.0)))"
  elif ((t >= 100000)); then out="$((t / 1000))k"
  elif ((t >= 1000)); then out="$(printf '%.1fk' $((t / 1000.0)))"
  else out="$t"; fi
  printf '%s' "${out/.0/}"
}

# Cache files: a private per-user folder, keyed by a checksum of what they describe.
# If the folder is a link, not yours, or open to others (someone got there first in a
# shared /tmp), nothing is cached and no PR title is fetched; the line still renders.
umask 077
CACHE_DIR="${TMPDIR:-/tmp}/claude-statusline-${UID}"
[[ -e "$CACHE_DIR" || -L "$CACHE_DIR" ]] || mkdir -m 700 "$CACHE_DIR" 2>/dev/null
CACHE_OK=0
[[ -d "$CACHE_DIR" && ! -L "$CACHE_DIR" && -O "$CACHE_DIR" ]] \
  && (( ($(zstat +mode "$CACHE_DIR" 2>/dev/null || print 63) & 8#077) == 0 )) && CACHE_OK=1
key() { print -rn -- "$1" | cksum | cut -d' ' -f1; }
age() { local m; m=$(zstat +mtime "$1" 2>/dev/null) || { print 999999; return; }; print $(($(date +%s) - m)); }

# Account: which login Claude Code is using. Labels and colours come from ACCOUNTS;
# an unknown login shows its address's local part, muted. SHOW_ACCOUNT=0 skips it all.
ACCT_EMAIL=""
((SHOW_ACCOUNT)) && ACCT_EMAIL="$(jq -r '.oauthAccount.emailAddress // empty' "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" 2>/dev/null)"
ACCT="" ACCT_BG="" ACCT_FG=""
for a in "${ACCOUNTS[@]}"; do
  [[ "${a%%|*}" == "$ACCT_EMAIL" ]] || continue
  IFS='|' read -r _ ACCT ACCT_BG ACCT_FG <<<"$a"
  break
done
if [[ -n "$ACCT" && -n "$ACCT_BG" ]]; then
  ACCT_C=$'\e[48;2;'"${ACCT_BG}m"$'\e[38;2;'"${ACCT_FG:-0;0;0}m${BOLD}"
  if ((PILL)); then
    # Rounded ends: Nerd Font half-circle caps (U+E0B6 / U+E0B4) in the chip colour.
    CAP=$'\e[38;2;'"${ACCT_BG}m"
    CHIP="${CAP}"$'\ue0b6'"${RESET}${ACCT_C}${ACCT}${RESET}${CAP}"$'\ue0b4'"${RESET}"
  else
    CHIP="${ACCT_C} ${ACCT} ${RESET}"
  fi
elif [[ -n "$ACCT_EMAIL" ]]; then
  CHIP="${MUTED}${ACCT:-${ACCT_EMAIL%%@*}}${RESET}"
elif ((SHOW_ACCOUNT)); then
  CHIP="${MUTED}no login${RESET}"
else
  CHIP=""
fi

# Git, cached 5s per folder so parallel tabs never read each other's branch.
BRANCH=""
git_branch() {
  git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { print; return; }
  local b="$(git -C "$DIR" branch --show-current 2>/dev/null)"
  [[ -z "$b" ]] && b="($(git -C "$DIR" rev-parse --short HEAD 2>/dev/null))"
  print -r -- "$b"
}
if [[ -n "$DIR" && -d "$DIR" ]]; then
  if ((CACHE_OK)); then
    CACHE="$CACHE_DIR/git-$(key "$DIR")"
    if [[ ! -f "$CACHE" ]] || (($(age "$CACHE") > 5)); then
      git_branch >"$CACHE.$$"
      mv -f "$CACHE.$$" "$CACHE" 2>/dev/null
    fi
    BRANCH="$(<"$CACHE")"
  else
    BRANCH="$(git_branch)"
  fi
  BRANCH="${BRANCH//[[:cntrl:]]/}"
fi

# PR: number from the JSON pr field, else from the branch name
# (pr/123, fix/pr-123, feature-pr123). The title comes from gh, cached per repo and
# PR for 1h and fetched in the background so the line never waits.
PR_FROM_BRANCH=""
[[ -z "$PR_NUM" && "$BRANCH" =~ '(^|[^a-z])pr[-/_]?([0-9]+)' ]] && PR_NUM="${match[2]}" PR_FROM_BRANCH=1
PR_TITLE=""
if ((PR_TITLES && CACHE_OK)) && [[ -n "$PR_NUM" && -n "$DIR" ]] && command -v gh >/dev/null 2>&1; then
  ROOT="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)"
  PR_CACHE="$CACHE_DIR/pr-$(key "${ROOT:-$DIR}#$PR_NUM")"
  [[ -f "$PR_CACHE" ]] && PR_TITLE="$(<"$PR_CACHE")"
  ttl=3600; [[ -z "$PR_TITLE" ]] && ttl=300
  if [[ ! -f "$PR_CACHE" ]] || (($(age "$PR_CACHE") > ttl)); then
    touch "$PR_CACHE" 2>/dev/null   # one fetch at a time
    ( cd "${ROOT:-$DIR}" && t="$(gh pr view "$PR_NUM" --json title -q .title 2>/dev/null)" \
        && t="${t//[[:cntrl:]]/}" && [[ -n "$t" ]] && print -r -- "$t" >"$PR_CACHE.tmp" && mv -f "$PR_CACHE.tmp" "$PR_CACHE" ) \
      </dev/null >/dev/null 2>&1 &!
  fi
fi

# --- Row 1: account chip, model · effort, folder · branch, ticket or PR, session name ---
# Ticket: the folder that TICKET_PATTERN captures from the working folder (off by default).
# Understood names, each with an optional leading date and an optional " - DONE" suffix:
# "[#123] Title-words", "Title-words-PR123" and "Title-words-123".
tmax=$TICKET_MAX; ((tmax > MAXW - 20)) && tmax=$((MAXW - 20))
ITEM="" PR_SHOWN=""
if [[ -n "$TICKET_PATTERN" && "$DIR" =~ $TICKET_PATTERN ]]; then
  tk="${${match[1]//[[:cntrl:]]/}#<->. }" tnum="" tdone=""
  tk="${tk#<->-<->-<-> }"; tk="${tk#- }"
  [[ "$tk" == *" - DONE" ]] && tdone=1 tk="${tk% - DONE}"
  if [[ "$tk" =~ '^\[#([0-9]+)\] *(.*)$' ]]; then tnum="#${match[1]}" tk="${match[2]}"
  elif [[ "$tk" =~ '^(.*)[-_ ]PR-?([0-9]+)$' ]]; then tnum="PR #${match[2]}" tk="${match[1]}"
  elif [[ "$tk" =~ '^(.*)-([0-9]+)$' ]]; then tnum="#${match[2]}" tk="${match[1]}"
  fi
  # Word-dashes to spaces (twice: a match consumes the letter after the dash).
  tk="${tk//(#b)([[:alnum:]])-([[:alnum:]])/${match[1]} ${match[2]}}"
  tk="${tk//(#b)([[:alnum:]])-([[:alnum:]])/${match[1]} ${match[2]}}"
  ((${#tk} > tmax)) && tk="${tk[1,tmax-1]}…"
  ITEM="${tnum:+${CYAN}${tnum}${RESET}}${tnum:+${tk:+ }}${tk:+${TEXT}${tk}${RESET}}${tdone:+ ${MUTED}(done)${RESET}}"
elif [[ -n "$PR_NUM" ]]; then
  tk="$PR_TITLE"; ((${#tk} > tmax)) && tk="${tk[1,tmax-1]}…"
  ITEM="${CYAN}PR #${PR_NUM}${RESET}${tk:+ ${TEXT}${tk}${RESET}}${PR_STATE:+ ${MUTED}(${PR_STATE//_/ })${RESET}}"
  PR_SHOWN=1
fi

parts=(); [[ -n "$CHIP" ]] && parts+=("$CHIP")
case "$MODEL" in
  *Opus*)  MODEL_C="$ORANGE" ;;
  *Fable*) MODEL_C="$PURPLE" ;;
  *)       MODEL_C="$CYAN" ;;
esac
[[ -n "$MODEL" ]] && parts+=("${MODEL_C}◆ ${MODEL}${RESET}${EFFORT:+ ${MUTED}· ${EFFORT}${RESET}}")

# Folder: the project, never the home folder name or a ticket folder.
# The project folder, unless the tab was opened in the home folder; then the working folder.
FOLDER="$PROJ"; [[ -z "$FOLDER" || "$FOLDER" == "$HOME" ]] && FOLDER="$DIR"
# Inside a ticket, the folder that holds the match (the pattern may start with "/" or not).
[[ -n "$TICKET_PATTERN" && "$FOLDER" =~ $TICKET_PATTERN ]] && FOLDER="${${FOLDER[1,MBEGIN]}%/*}"
if [[ -n "$FOLDER" ]]; then
  f="${${FOLDER:t}//[[:cntrl:]]/}"; [[ "$FOLDER" == "$HOME" ]] && f="~"
  f="${PURPLE}${f}${RESET}"
  [[ -n "$BRANCH" && ! ( -n "$PR_SHOWN" && -n "$PR_FROM_BRANCH" ) ]] && f+=" ${MUTED}·${RESET} ${PINK}${BRANCH}${RESET}"
  parts+=("$f")
fi
[[ -n "$ITEM" ]] && parts+=("$ITEM")
[[ -n "$AGENT" ]] && parts+=("${MUTED}agent ${AGENT}${RESET}")
[[ -n "$VIM" ]] && parts+=("${MUTED}[${VIM}]${RESET}")
[[ -n "$STYLE" && "$STYLE" != "default" ]] && parts+=("${MUTED}style: ${STYLE}${RESET}")

rows=("${(@f)$(emit "${parts[@]}")}"); rows=("${(@)rows:#}")   # no parts, no row

# --- Row 2: context, 5h and 7d bars, cost ---
COST_PART=""
[[ -n "$COST" ]] && COST_PART="${GREEN}\$$(printf '%.2f' "$COST")${RESET}"
P5=""; [[ -n "$R5" ]] && P5="$(pace "$R5_AT" 18000)"
P7=""; [[ -n "$R7" ]] && P7="$(pace "$R7_AT" 604800)"
limit_part() {   # $1 label  $2 percent  $3 resets_at  $4 pace
  local r="" p="$(to_int "$2")"
  ((p >= 70)) && r="$(reset_in "$3")"
  print -r -- "$1 $(bar "$2" "$4")${r:+ ${MUTED}↻ ${r}${RESET}}"
}
limit_parts() {
  parts=()
  if [[ -n "$CTX" ]]; then
    local size="$(to_int "$CTX_SIZE")" label="ctx"
    ((size > 0 && size != 200000)) && label+=" $(tokens $size)"
    if [[ "$BIG" == "true" ]]; then label="${RED}${label} >200k${RESET}"
    else label="${MUTED}${label}${RESET}"; fi
    parts+=("$(limit_part "$label" "$CTX" "" "")")
  fi
  [[ -n "$R5" ]] && parts+=("$(limit_part "${MUTED}5h${RESET}" "$R5" "$R5_AT" "$P5")")
  [[ -n "$R7" ]] && parts+=("$(limit_part "${MUTED}7d${RESET}" "$R7" "$R7_AT" "$P7")")
  [[ -n "$COST_PART" ]] && parts+=("$COST_PART")
}
# Widest bars that fit one row; at 4 cells, drop the cost, then wrap.
fits() { (($(vis_width "${(pj:$SEP:)parts}") <= MAXW)); }
for BAR_W in 10 8 6 4; do limit_parts; fits && break; done
[[ -n "$COST_PART" ]] && ! fits && parts[-1]=()

# Session name: it joins the last line of row 1 only, shortened to the room left, and is
# dropped rather than starting a line of its own. /rename <name>, or CLAUDE_TASK=<name>.
TASK="${CLAUDE_TASK:-$SESSION}"
TASK="${TASK//[[:cntrl:]]/}"
if [[ -n "$TASK" ]]; then
  ((${#TASK} > 40)) && TASK="${TASK[1,39]}…"
  if ((${#rows})); then room=$((MAXW - $(vis_width "${rows[-1]}") - SEP_W)); else room=$MAXW; fi
  ((${#TASK} > room && room >= 12)) && TASK="${TASK[1,room-1]}…"
  if ((${#TASK} <= room)); then
    if ((${#rows})); then rows[-1]+="${SEP}${MUTED}${TASK}${RESET}"; else rows=("${MUTED}${TASK}${RESET}"); fi
  fi
fi
((${#rows})) && printf '%s\n' "${rows[@]}"
((${#parts})) && emit "${parts[@]}"
exit 0
