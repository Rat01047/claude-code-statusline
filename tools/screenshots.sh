#!/bin/zsh
# Render docs/screenshots/*.svg from made-up sessions. Usage: zsh tools/screenshots.sh
export LC_ALL=en_US.UTF-8
ROOT=${0:A:h:h}
F=$ROOT/statusline.sh FX=$ROOT/tests/fixtures OUT=$ROOT/docs/screenshots
mkdir -p $OUT

W=$(mktemp -d "${TMPDIR:-/tmp}/statusline-shots.XXXXXX")
trap 'rm -rf "$W"' EXIT
mkdir -p $W/home $W/tmp $W/bin
export HOME=$W/home TMPDIR=$W/tmp XDG_CONFIG_HOME=$W/xdg
export CLAUDE_CONFIG_DIR=$FX/work CLAUDE_STATUSLINE_CONF=$FX/config.zsh
unset CLAUDE_TASK

A=$W/Acme-Shop
T="$A/tickets/2026-10-28 [#42] Coupon-applies-twice"
mkdir -p "$T/notes"
now=$(date +%s)
mk() {  # $1 dir  $2 ctx%  $3 5h%  $4 7d%  $5 5h seconds left  $6 session name  [$7 model]
  jq -n --arg d "$1" --arg p "$A" --argjson c $2 --argjson f $3 --argjson s $4 \
    --argjson a5 $((now + $5)) --argjson a7 $((now + 129600)) --arg n "$6" --arg m "${7:-Opus 5.5}" \
    '{model:{display_name:$m},effort:{level:"high"},session_name:$n,
      workspace:{current_dir:$d,project_dir:$p},
      context_window:{used_percentage:$c,context_window_size:200000},
      rate_limits:{five_hour:{used_percentage:$f,resets_at:$a5},seven_day:{used_percentage:$s,resets_at:$a7}},
      cost:{total_cost_usd:3.12}}'
}
shot() {  # $1 name  $2 columns  $3 title  $4 json  [env...]
  local name=$1 cols=$2 title=$3 json=$4; shift 4
  print -r -- "$json" | env COLUMNS=$cols "$@" "$F" | python3 $ROOT/tools/ansi2svg.py --title "$title" >$OUT/$name.svg
  print -r -- "$OUT/$name.svg"
}

shot wide 112 "Inside a ticket folder, with TICKET_PATTERN set" "$(mk "$T/notes" 65 74 30 10320 "Checkout refactor")"
shot limits 112 "Near the limits: red percent, reset times" \
  "$(mk "$T" 88 92 81 1500 "Checkout refactor")" CLAUDE_CONFIG_DIR=$FX/home

# A PR branch in a git repo; a stand-in gh supplies the title.
G=$W/Acme-Api
git init -q -b fix/pr-123 $G && git -C $G -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
print -r -- '#!/bin/sh'$'\n''echo "Fix coupon stacking on bundles"' >$W/bin/gh; chmod +x $W/bin/gh
J=$(mk "$G" 34 18 22 14000 "Review PR 123" "Fable 5.1" | jq --arg g "$G" '.workspace.project_dir=$g')
print -r -- "$J" | PATH=$W/bin:$PATH COLUMNS=112 "$F" >/dev/null
for i in {1..30}; do [[ -n "$(cat $TMPDIR/claude-statusline-$UID/pr-*(N) 2>/dev/null)" ]] && break; sleep 0.1; done
shot pr 112 "On a PR branch" "$J" PATH=$W/bin:$PATH

shot narrow 60 "A narrow pane (60 columns)" "$(mk "$T/notes" 65 74 30 10320 "Checkout refactor")"
