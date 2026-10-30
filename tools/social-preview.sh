#!/usr/bin/env zsh
# Rebuild docs/social-preview.png (1280x640) from the wide and limits screenshots.
# macOS only: renders with Quick Look (qlmanage) and crops with sips.
# Run tools/screenshots.sh first so the screenshots are current.
set -e
cd "${0:A:h}/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
F="'JetBrains Mono','SF Mono',Menlo,monospace"
inner() { sed '1d;$d' "$1"; }   # an SVG's body, without its outer <svg> tags
{
  # qlmanage renders on a square canvas, so the 1280x640 card sits in the middle of a 1280x1280 view.
  print -r -- '<svg xmlns="http://www.w3.org/2000/svg" width="768" height="768" viewBox="0 -320 1280 1280">'
  print -r -- '<rect x="0" y="-320" width="1280" height="1280" fill="#1e1f29"/>'
  print -r -- "<text x=\"80\" y=\"118\" fill=\"#f8f8f2\" font-family=\"$F\" font-size=\"58\" font-weight=\"bold\">claude-code-statusline</text>"
  print -r -- "<text x=\"80\" y=\"178\" fill=\"#bd93f9\" font-family=\"$F\" font-size=\"26\">A two-row status line for Claude Code.</text>"
  print -r -- "<text x=\"80\" y=\"220\" fill=\"#6272a4\" font-family=\"$F\" font-size=\"22\">The <tspan fill=\"#ff79c6\" font-weight=\"bold\">│</tspan> pace marker shows when you burn a limit faster than it refills.</text>"
  print -r -- '<svg x="80" y="262" width="1121" height="146" viewBox="0 0 801 104">'; inner docs/screenshots/wide.svg; print -r -- '</svg>'
  print -r -- '<svg x="80" y="436" width="1121" height="146" viewBox="0 0 801 104">'; inner docs/screenshots/limits.svg; print -r -- '</svg>'
  print -r -- '</svg>'
} > "$tmp/card.svg"
qlmanage -t -s 1280 -o "$tmp" "$tmp/card.svg" >/dev/null 2>&1
sips -c 640 1280 "$tmp/card.svg.png" --out docs/social-preview.png >/dev/null
print "wrote docs/social-preview.png"
