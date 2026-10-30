#!/bin/zsh
# Assertions on the rendered status line, using made-up accounts and folders only.
# Usage: zsh tests/run.sh [path/to/statusline.sh]
# Needs zsh, jq and git.
export LC_ALL=en_US.UTF-8
HERE=${0:A:h}
F=${1:-$HERE/../statusline.sh}; F=${F:A}
FX=$HERE/fixtures

# Isolated world: a scratch HOME, cache folder and config, so nothing real is read or written.
W=$(mktemp -d "${TMPDIR:-/tmp}/statusline-test.XXXXXX")
trap 'rm -rf "$W"' EXIT
mkdir -p $W/home $W/tmp $W/bin
export HOME=$W/home TMPDIR=$W/tmp XDG_CONFIG_HOME=$W/xdg
export CLAUDE_CONFIG_DIR=$FX/work CLAUDE_STATUSLINE_CONF=$FX/config.zsh
unset CLAUDE_TASK

A=$W/Acme-Shop
T="$A/tickets/2026-10-28 [#42] Coupon-applies-twice"
D="$A/tickets/2026-09-30 [#17] Guest-checkout-email-missing - DONE"
mkdir -p "$T/notes" "$D"

# Plain text for the checks: track cells read as ░ and filled cells as █, colours removed.
strip() { sed -e $'s/\x1b\\[38;2;68;71;90m■/░/g' -e 's/■/█/g' -e $'s/\x1b\\[[0-9;]*m//g'; }
pass=0 fail=0
ok()  { print -r -- "PASS  $1"; ((pass++)); }
bad() { print -r -- "FAIL  $1"; print -r -- "$2" | sed 's/^/      | /'; ((fail++)); }
check() { local name=$1 out=$2; shift 2; if eval "$@"; then ok "$name"; else bad "$name" "$out"; fi; }
line() { print -r -- "$1" | sed -n "${2}p"; }
CAPL=$'\ue0b6' CAPR=$'\ue0b4'

now=$(date +%s)
mk() {  # $1 dir  $2 project  $3 ctx%  $4 5h%  $5 7d%
  jq -n --arg d "$1" --arg p "$2" --argjson c $3 --argjson f $4 --argjson s $5 \
    --argjson a5 $((now + 10320)) --argjson a7 $((now + 129600)) \
    '{model:{display_name:"Opus 5.5"},effort:{level:"high"},session_name:"Checkout refactor",
      workspace:{current_dir:$d,project_dir:$p},
      context_window:{used_percentage:$c,context_window_size:200000},
      rate_limits:{five_hour:{used_percentage:$f,resets_at:$a5},seven_day:{used_percentage:$s,resets_at:$a7}},
      cost:{total_cost_usd:3.12}}'
}
run() { print -r -- "$1" | COLUMNS=$2 "$F"; }

# 1. Wide, inside a subfolder of a ticket: row 1 and row 2, no blank line between.
R=$(run "$(mk "$T/notes" "$A" 65 74 30)" 157); P=$(print -r -- "$R" | strip)
check "wide: 2 lines" "$P" '(( $(print -r -- "$P" | wc -l) == 2 ))'
check "row 1: chip, model · effort, product folder, ticket, session name" "$P" \
  '[[ "$(line "$P" 1)" == "${CAPL}Work${CAPR} │ ◆ Opus 5.5 · high │ Acme-Shop │ #42 Coupon applies twice │ Checkout refactor" ]]'
check "row 2: CTX, 5h with pace and reset, 7d with pace, cost" "$P" \
  '[[ "$(line "$P" 2)" == "CTX ██████░░░░ 65% │ 5h ████│██░░░ 74% ↻ 2h52m │ 7d ███░░░░│░░ 30% │ \$3.12" ]]'
check "exactly one bold run (the chip)" "$R" '(( $(print -r -- "$R" | grep -o $'"'"'\e\\[1m'"'"' | wc -l) == 1 ))'
check "no emoji" "$P" '! print -r -- "$P" | LC_ALL=C grep -q $'"'"'\xf0\x9f'"'"''
check "chip: configured background and text colour, caps in chip colour" "$R" \
  '[[ "$R" == *$'"'"'\e[38;2;10;186;181m\e[0m\e[48;2;10;186;181m\e[38;2;0;0;0m\e[1mWork'"'"'* ]]'
check "dracula: Opus orange, folder purple, ticket number cyan, title foreground, cost green" "$R" \
  '[[ "$R" == *"38;2;255;184;108m◆ Opus 5.5"* && "$R" == *"38;2;189;147;249mAcme-Shop"* && "$R" == *"38;2;139;233;253m#42"* && "$R" == *"38;2;248;248;242mCoupon applies"* && "$R" == *"38;2;80;250;123m\$3.12"* ]]'
check "separators comment grey, track current-line grey, pace marker pink" "$R" \
  '[[ "$R" == *$'"'"'\e[38;2;98;114;164m│'"'"'* && "$R" == *"38;2;68;71;90m■"* && "$R" == *"38;2;255;121;198m│"* ]]'
check "bars are ■ cells, sitting on the text baseline; no lines, blocks or shades" "$R" \
  '[[ "$R" == *■* && "$R" != *━* && "$R" != *▆* && "$R" != *█* && "$R" != *░* ]]'
check "gradient: ctx bar has 6 different cell colours, first is the dimmed green" "$R" \
  '(( $(line "$R" 2 | grep -o $'"'"'\e\\[38;2;[0-9;]*m■'"'"' | head -6 | sort -u | wc -l) == 6 )) && [[ "$R" == *"38;2;74;219;113m■"* ]]'
check "percent colour: 65% and 74% yellow, 30% green" "$R" \
  '[[ "$R" == *"38;2;241;250;140m65%"* && "$R" == *"38;2;241;250;140m74%"* && "$R" == *"38;2;80;250;123m30%"* ]]'

# 2. Red from 80%; no reset times below 70%.
R=$(run "$(mk "$T" "$A" 90 30 20)" 157)
check "ctx 90%: percent red" "$R" '[[ "$R" == *"38;2;255;85;85m90%"* ]]'
check "all limits under 70%: no reset time" "$R" '[[ "$R" != *"↻"* ]]'

# 3. Project root: no ticket. Tab opened in the home folder: folder comes from the working folder.
P=$(run "$(mk "$A" "$A" 40 30 20)" 157 | strip)
check "project root: no ticket part" "$P" '[[ "$(line "$P" 1)" == *"│ Acme-Shop │ Checkout refactor" ]]'
P=$(run "$(mk "$A" "$HOME" 40 30 20)" 157 | strip)
check "home as project: folder = Acme-Shop" "$P" '[[ "$P" == *"│ Acme-Shop │"* && "$P" != *"│ home │"* ]]'
P=$(run "$(mk "$T/notes" "$HOME" 40 30 20)" 157 | strip)
check "home as project, inside a ticket: folder = the project above tickets/" "$P" \
  '[[ "$(line "$P" 1)" == *"│ Acme-Shop │ #42 Coupon applies twice │"* ]]'

# 4. A DONE ticket folder shows (done).
P=$(run "$(mk "$D" "$A" 40 30 20)" 157 | strip)
check "done ticket shows (done)" "$P" '[[ "$P" == *"#17 Guest checkout email missing (done)"* ]]'

# 5. Every row fits at every width, in at most 3 lines.
for c in 60 72 75 100 157; do
  P=$(run "$(mk "$T/notes" "$A" 65 74 30)" $c | strip)
  w=0; while IFS= read -r l; do ((${(m)#l} > w)) && w=${(m)#l}; done <<<"$P"
  check "COLUMNS=$c: widest row $w <= $((c - 2)), $(print -r -- "$P" | wc -l | tr -d ' ') lines <= 3" "$P" \
    '(( w <= c - 2 && $(print -r -- "$P" | wc -l) <= 3 ))'
done

# 6. Accounts: a second login, an unknown login, no config at all, square chip.
R=$(print -r -- "$(mk "$A" "$A" 40 30 20)" | CLAUDE_CONFIG_DIR=$FX/home COLUMNS=157 "$F")
check "home login: its chip colour once, not the work colour" "$R" \
  '(( $(print -r -- "$R" | grep -o "48;2;34;139;34m" | wc -l) == 1 )) && [[ "$R" != *"10;186;181m"* && "$(line "$R" 1 | strip)" == "${CAPL}Home${CAPR} │"* ]]'
R=$(print -r -- "$(mk "$A" "$A" 40 30 20)" | CLAUDE_CONFIG_DIR=$FX/other COLUMNS=157 "$F")
check "unknown login: address local part, muted, no chip" "$R" \
  '[[ "$(line "$R" 1)" == $'"'"'\e[38;2;98;114;164msomeone\e[0m'"'"'* && "$R" != *"48;2;"* ]]'
R=$(print -r -- "$(mk "$A" "$A" 40 30 20)" | CLAUDE_STATUSLINE_CONF=$W/none.zsh COLUMNS=157 "$F")
check "no config file: still renders, login shown muted" "$R" \
  '[[ "$(line "$R" 1 | strip)" == "work │ ◆ Opus 5.5"* && "$R" != *"48;2;"* ]]'
P=$(print -r -- "$(mk "$T" "$A" 40 30 20)" | CLAUDE_STATUSLINE_CONF=$W/none.zsh COLUMNS=157 "$F" | strip)
check "no config file: ticket parsing is off by default" "$P" '[[ "$P" != *"#42"* && "$P" != *"Coupon"* ]]'
print -r -- "source $FX/config.zsh; PILL=0" >$W/square.zsh
R=$(print -r -- "$(mk "$A" "$A" 40 30 20)" | CLAUDE_STATUSLINE_CONF=$W/square.zsh COLUMNS=157 "$F")
check "PILL=0: padded square chip, no Nerd Font caps" "$R" \
  '[[ "$(line "$R" 1 | strip)" == " Work  │"* && "$R" != *$CAPL* ]]'
print -r -- "source $FX/config.zsh; SHOW_ACCOUNT=0" >$W/nochip.zsh
P=$(print -r -- "$(mk "$A" "$A" 40 30 20)" | CLAUDE_STATUSLINE_CONF=$W/nochip.zsh COLUMNS=157 "$F" | strip)
check "SHOW_ACCOUNT=0: no chip, row 1 starts at the model" "$P" '[[ "$(line "$P" 1)" == "◆ Opus 5.5 · high │ Acme-Shop │"* && "$P" != *Work* ]]'
print -r -- "SHOW_ACCOUNT=0" >$W/nochip2.zsh
P=$(print -r -- "$(mk "$A" "$A" 40 30 20)" | CLAUDE_STATUSLINE_CONF=$W/nochip2.zsh CLAUDE_CONFIG_DIR=$FX/other COLUMNS=157 "$F" | strip)
check "SHOW_ACCOUNT=0 with an unknown login: its name is not shown either" "$P" '[[ "$P" != *someone* && "$(line "$P" 1)" == "◆ Opus 5.5"* ]]'
P=$(print -r -- '{}' | CLAUDE_STATUSLINE_CONF=$W/nochip.zsh COLUMNS=157 "$F" 2>&1 | strip)
check "SHOW_ACCOUNT=0 with empty JSON: no output at all, no error" "$(print -r -- "$P" | od -c)" '[[ -z "$P" ]] && (( $(print -r -- '"'"'{}'"'"' | CLAUDE_STATUSLINE_CONF=$W/nochip.zsh COLUMNS=157 "$F" | wc -c) == 0 ))'
P=$(print -r -- '{"session_name":"Solo"}' | CLAUDE_STATUSLINE_CONF=$W/nochip.zsh COLUMNS=157 "$F" | strip)
check "SHOW_ACCOUNT=0, only a session name: the name alone, no leading separator" "$P" '[[ "$P" == "Solo" ]]'
print -r -- "source $FX/config.zsh; TICKET_PATTERN=''" >$W/noticket.zsh
P=$(print -r -- "$(mk "$T" "$A" 40 30 20)" | CLAUDE_STATUSLINE_CONF=$W/noticket.zsh COLUMNS=157 "$F" | strip)
check "TICKET_PATTERN='': ticket parsing off" "$P" '[[ "$P" != *"#42"* ]]'

# 6b. The shipped example config loads without errors and colours its login.
mkdir -p $W/ex && print -r -- '{"oauthAccount":{"emailAddress":"you@company.example"}}' >$W/ex/.claude.json
E=$(print -r -- "$(mk "$A" "$A" 40 30 20)" | CLAUDE_STATUSLINE_CONF=${HERE:h}/config.example.zsh CLAUDE_CONFIG_DIR=$W/ex COLUMNS=157 "$F" 2>&1)
check "config.example.zsh: no errors, Work chip" "$E" \
  '[[ "$E" != *"statusline.sh:"* && "$(line "$E" 1 | strip)" == "${CAPL}Work${CAPR} │"* && "$E" == *"48;2;10;186;181m"* ]]'
sed 's/^# *TICKET_PATTERN=/TICKET_PATTERN=/' ${HERE:h}/config.example.zsh >$W/ex.zsh
P=$(print -r -- "$(mk "$T" "$A" 40 30 20)" | CLAUDE_STATUSLINE_CONF=$W/ex.zsh CLAUDE_CONFIG_DIR=$W/ex COLUMNS=157 "$F" | strip)
check "config.example.zsh: its commented TICKET_PATTERN, switched on, finds the ticket" "$P" '[[ "$P" == *"│ #42 Coupon applies twice │"* ]]'

# 7. Empty input still renders the chip, and nothing else.
P=$(print -r -- '{}' | COLUMNS=157 "$F" | strip)
check "empty JSON: the chip only" "$P" '[[ "$P" == "${CAPL}Work${CAPR}" ]]'

# 8. Git: branch beside the folder; a PR branch shows the PR instead.
G=$W/Acme-Api
git init -q -b main $G && git -C $G -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
P=$(run "$(mk "$G" "$G" 40 30 20)" 157 | strip)
check "git: folder · branch" "$P" '[[ "$P" == *"│ Acme-Api · main │"* ]]'
git -C $G checkout -q -b fix/pr-123
rm -f $TMPDIR/claude-statusline-$UID/git-*   # the branch is cached 5s; skip the wait
print -r -- "source $FX/config.zsh; PR_TITLES=0" >$W/nogh.zsh
print -r -- '#!/bin/sh'$'\n''touch "'$W'/gh-called"; echo "Fix coupon stacking"' >$W/bin/gh; chmod +x $W/bin/gh
P=$(print -r -- "$(mk "$G" "$G" 40 30 20)" | PATH=$W/bin:$PATH CLAUDE_STATUSLINE_CONF=$W/nogh.zsh COLUMNS=157 "$F" | strip)
sleep 1
check "PR branch: PR #123 shown, branch hidden" "$P" '[[ "$P" == *"│ Acme-Api │ PR #123 │"* ]]'
check "PR_TITLES=0: gh never called" "$P" '[[ ! -e $W/gh-called ]]'
print -r -- "$(mk "$G" "$G" 40 30 20)" | PATH=$W/bin:$PATH COLUMNS=157 "$F" >/dev/null
for i in {1..20}; do [[ -n "$(cat $TMPDIR/claude-statusline-$UID/pr-*(N) 2>/dev/null)" ]] && break; sleep 0.1; done
P=$(print -r -- "$(mk "$G" "$G" 40 30 20)" | PATH=$W/bin:$PATH COLUMNS=157 "$F" | strip)
check "PR title fetched by gh in the background, shown on the next render" "$P" \
  '[[ -e $W/gh-called && "$P" == *"PR #123 Fix coupon stacking"* ]]'

# 9. Control characters in names never reach the terminal: a folder, ticket or model name
# carrying escape codes (window title, clear screen, C1 CSI) prints as plain text.
ESC=$'\e' BEL=$'\a' CSI1=$'\u009b'
E="$W/Evil${ESC}]0;pwned${BEL}Shop"
ET="$E/tickets/[#9] Bad${ESC}[2J-name"
mkdir -p "$ET"
J=$(mk "$ET" "$E" 40 30 20 | jq --arg m "Opus${ESC}[31m${CSI1}5J" --arg x "x${ESC}[2Jy" \
  '.model.display_name=$m | .effort.level=$x | .agent.name=$x | .vim.mode=$x | .output_style.name=$x | .pr.review_state=$x')
R=$(run "$J" 157)
NOSGR=$(print -r -- "$R" | sed $'s/\x1b\\[[0-9;]*m//g' | tr -d '\n')
check "escape codes in names: only colour codes reach the terminal" "$(print -r -- "$R" | cat -v)" \
  '[[ "$NOSGR" != *[[:cntrl:]]* ]]'
P=$(print -r -- "$R" | strip)
check "escape codes in names: the names still show as text" "$P" \
  '[[ "$P" == *"Evil]0;pwnedShop"* && "$P" == *"#9 Bad[2J name"* && "$P" == *"◆ Opus[31m5J"* ]]'

# 10. Untrusted input and shared folders.
C=$TMPDIR/claude-statusline-$UID
mkdir -p $W/bin2
print -r -- '#!/bin/sh'$'\n''echo "$@" >>"'$W'/gh-args"; echo "Spoofed title"' >$W/bin2/gh; chmod +x $W/bin2/gh
J=$(mk "$A" "$A" 40 30 20 | jq '.pr.number="--web"')
P=$(print -r -- "$J" | PATH=$W/bin2:$PATH COLUMNS=157 "$F" | strip); sleep 0.5
check "pr.number not a number: gh never called, no PR part" "$P" '[[ ! -e $W/gh-args && "$P" != *"--web"* && "$P" != *"PR #"* ]]'

git -C $G checkout -q main
chmod 777 $C; rm -f $C/*(N)
P=$(run "$(mk "$G" "$G" 40 30 20)" 157 | strip)
check "cache folder open to others: nothing written to it, branch still shown" "$P $(ls -A $C)" \
  '[[ -z "$(ls -A $C)" && "$P" == *"│ Acme-Api · main │"* ]]'
chmod 700 $C

mv $C $W/real-cache; mkdir -p $W/elsewhere; ln -s $W/elsewhere $C
P=$(run "$(mk "$G" "$G" 40 30 20)" 157 | strip)
check "cache folder is a symlink: nothing written through it, branch still shown" "$P $(ls -A $W/elsewhere)" \
  '[[ -z "$(ls -A $W/elsewhere)" && "$P" == *"│ Acme-Api · main │"* ]]'
rm $C; mv $W/real-cache $C

cp $FX/config.zsh $W/open.zsh; chmod 666 $W/open.zsh
R=$(print -r -- "$(mk "$A" "$A" 40 30 20)" | CLAUDE_STATUSLINE_CONF=$W/open.zsh COLUMNS=157 "$F")
check "config writable by others: not loaded (no chip colours)" "$(print -r -- "$R" | strip)" '[[ "$R" != *"48;2;"* ]]'

# 11. Cache files live in a private per-user folder.
C=$TMPDIR/claude-statusline-$UID
check "cache folder is $C:t, mode 700" "$(ls -ld $C 2>&1)" '[[ -d $C && $(stat -f %Lp $C 2>/dev/null || stat -c %a $C) == 700 ]]'

print -r -- "---- $pass passed, $fail failed"
((fail == 0))
