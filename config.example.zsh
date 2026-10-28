# Copy to ~/.config/claude-statusline/config.zsh (or point CLAUDE_STATUSLINE_CONF at it).
# Every setting is optional; delete what you don't need.

# Account chip: one entry per login, "email|Label|background r;g;b|text r;g;b".
# The email is the one Claude Code shows under /status. A login not listed here
# shows the part of its address before the @, in grey.
ACCOUNTS=(
  'you@company.example|Work|10;186;181|0;0;0'
  'you@personal.example|Personal|34;139;34|255;255;255'
)

# Rounded chip ends. Needs a Nerd Font in your terminal; 0 gives a square chip.
PILL=1

# Ticket, read from the working folder. Off by default. If you keep one folder per ticket,
# point this regex at your layout; match[1] must capture the ticket folder's name.
# This one matches ".../my-project/tickets/2026-10-28 [#42] Coupon-applies-twice" and shows
# "#42 Coupon applies twice". A folder name ending in " - DONE" adds "(done)".
# TICKET_PATTERN='/tickets/([^/]+)'
TICKET_MAX=40

# PR title from `gh pr view` (run in the background, cached for an hour). 0 = never call gh.
PR_TITLES=1
