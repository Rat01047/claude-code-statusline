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

# Progress row: a made-up task list and running helpers in a scratch config folder, with the
# usual advisor time (7m) already in the estimate cache.
P=$W/cfg; mkdir -p $P/tasks/s-1 $P/projects/acme/s-1/subagents $P/projects/acme/s-2/subagents
cp $FX/work/.claude.json $P/
i=0; for t in "Read the spec" "Map the checkout code" "Write coupon tests" "Fix double discount" \
  "Fix bundle rounding" "Run the suite" "Review the diff" "Update the changelog" "Open the PR"; do
  ((i++)); s=pending; ((i <= 6)) && s=completed; ((i == 7)) && s=in_progress
  printf '{"id":"%s","subject":"%s","status":"%s"}' $i "$t" $s >$P/tasks/s-1/$i.json
done
zmodload zsh/datetime
helper() {  # $1 session  $2 id  $3 type  $4 seconds running
  printf '{"agentType":"%s","description":"Second opinion"}' $3 >$P/projects/acme/$1/subagents/agent-$2.meta.json
  print -r -- "{\"timestamp\":\"$(TZ=UTC strftime '%Y-%m-%dT%H:%M:%S.000Z' $((now - $4)))\"}" >$P/projects/acme/$1/subagents/agent-$2.jsonl
}
helper s-1 a1 advisor 192
helper s-2 a2 advisor 540; helper s-2 a3 advisor 680
C=$TMPDIR/claude-statusline-$UID; mkdir -p -m 700 $C
print 420 >$C/est-$(print -rn -- advisor | cksum | cut -d' ' -f1)
sid() { jq --arg s $1 '. + {session_id: $s}'; }
shot progress 112 "Progress row: Claude's task list and a running advisor, on track" \
  "$(mk "$T/notes" 41 38 30 10320 "Checkout refactor" | sid s-1)" CLAUDE_CONFIG_DIR=$P
shot progress-over 112 "An advisor past its usual time, with a second one running" \
  "$(mk "$T/notes" 58 52 33 10320 "Checkout refactor" | sid s-2)" CLAUDE_CONFIG_DIR=$P
