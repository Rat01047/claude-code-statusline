#!/usr/bin/env python3
"""Render 24-bit ANSI terminal text (stdin) as an SVG terminal snippet (stdout).

Understands the escape codes statusline.sh emits: reset, bold, 38;2 and 48;2 colours.
Block and square glyphs and the Nerd Font chip caps are drawn as shapes, so the picture does not
depend on the viewer having those fonts.

Usage: ... | python3 tools/ansi2svg.py [--title TEXT] > out.svg
"""
import re
import sys
from html import escape

CW, LH, FS = 9.0, 22, 15          # cell width, line height, font size (px)
PAD, BAR = 18, 30                 # frame padding, title bar height
BG, FG, MUTED = "#282a36", "#f8f8f2", "#6272a4"
FONT = "'JetBrains Mono','SF Mono',Menlo,Consolas,'DejaVu Sans Mono',monospace"
SGR = re.compile(r"\x1b\[([0-9;]*)m")
BLOCKS = {"█": 1.0, "▇": 7 / 8, "▆": 3 / 4, "▅": 5 / 8, "▄": 1 / 2}
SQUARE, SQ_H = "■", 0.58         # black square: baseline to x-height, full cell wide (in em)
SHAPES = "".join(BLOCKS) + "░" + SQUARE   # drawn, never set as text


def cells(line):
    """Yield (char, fg, bg, bold) for each column of one line."""
    fg, bg, bold = FG, None, False
    pos = 0
    for m in SGR.finditer(line + "\x1b[m"):
        for ch in line[pos:m.start()]:
            yield ch, fg, bg, bold
        pos = m.end()
        p = [int(x) for x in m.group(1).split(";") if x] or [0]
        i = 0
        while i < len(p):
            if p[i] == 0:
                fg, bg, bold = FG, None, False
            elif p[i] == 1:
                bold = True
            elif p[i] in (38, 48) and i + 4 < len(p) and p[i + 1] == 2:
                c = "#%02x%02x%02x" % tuple(p[i + 2:i + 5])
                if p[i] == 38:
                    fg = c
                else:
                    bg = c
                i += 4
            i += 1


def render(lines, title):
    rows = [list(cells(l)) for l in lines]
    cols = max((len(r) for r in rows), default=0)
    w = PAD * 2 + cols * CW
    h = BAR + PAD * 2 + len(rows) * LH - 6
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:.0f}" height="{h}" viewBox="0 0 {w:.0f} {h}">',
        f'<rect width="100%" height="100%" rx="10" fill="{BG}"/>',
    ]
    for i, c in enumerate(("#ff5555", "#f1fa8c", "#50fa7b")):
        out.append(f'<circle cx="{PAD + 6 + i * 20}" cy="{BAR // 2 + 4}" r="6" fill="{c}"/>')
    if title:
        out.append(f'<text x="{w / 2:.0f}" y="{BAR // 2 + 9}" fill="{MUTED}" font-family="{FONT}" '
                   f'font-size="13" text-anchor="middle">{escape(title)}</text>')
    for r, row in enumerate(rows):
        top = BAR + PAD + r * LH - 4
        base = top + LH * 0.75   # puts capitals on the cell's middle, as terminals do
        for c, (ch, fg, bg, bold) in enumerate(row):
            x = PAD + c * CW
            if bg:
                out.append(f'<rect x="{x:.1f}" y="{top}" width="{CW + 0.4:.1f}" height="{LH}" fill="{bg}"/>')
            if ch in BLOCKS:
                hh = LH * BLOCKS[ch]
                out.append(f'<rect x="{x:.1f}" y="{top + LH - hh:.1f}" width="{CW + 0.4:.1f}" height="{hh:.1f}" fill="{fg}"/>')
            elif ch == SQUARE:
                out.append(f'<rect x="{x:.1f}" y="{base + 0.03 * FS - SQ_H * FS:.1f}" width="{CW + 0.4:.1f}" height="{SQ_H * FS:.1f}" fill="{fg}"/>')
            elif ch == "░":
                out.append(f'<rect x="{x:.1f}" y="{top}" width="{CW + 0.4:.1f}" height="{LH}" fill="{fg}" opacity=".3"/>')
            elif ch == "\ue0b6":   # left half-circle cap
                out.append(f'<path d="M{x + CW + 0.4:.1f},{top} A{LH / 2},{LH / 2} 0 0 0 {x + CW + 0.4:.1f},{top + LH} Z" fill="{fg}"/>')
            elif ch == "\ue0b4":   # right half-circle cap
                out.append(f'<path d="M{x:.1f},{top} A{LH / 2},{LH / 2} 0 0 1 {x:.1f},{top + LH} Z" fill="{fg}"/>')
        # Text runs of one style, each stretched to its exact cell span.
        c = 0
        while c < len(row):
            ch, fg, bg, bold = row[c]
            if ch == " " or ch in SHAPES:
                c += 1
                continue
            e = c
            while e < len(row) and row[e][1:] == row[c][1:] and row[e][0] != " " \
                    and row[e][0] not in SHAPES:
                e += 1
            # let single spaces inside one style join the run (keeps words together)
            while e + 1 < len(row) and row[e][0] == " " and row[e][1:] == row[c][1:] \
                    and row[e + 1][1:] == row[c][1:] and row[e + 1][0] not in SHAPES:
                e += 2
                while e < len(row) and row[e][1:] == row[c][1:] and row[e][0] != " " \
                        and row[e][0] not in SHAPES:
                    e += 1
            text = "".join(t[0] for t in row[c:e])
            weight = ' font-weight="bold"' if bold else ""
            out.append(f'<text x="{PAD + c * CW:.1f}" y="{base:.1f}" fill="{fg}" font-family="{FONT}" '
                       f'font-size="{FS}"{weight} textLength="{(e - c) * CW:.1f}" lengthAdjust="spacingAndGlyphs" '
                       f'xml:space="preserve">{escape(text)}</text>')
            c = e
    out.append("</svg>")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    title = sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == "--title" else ""
    text = sys.stdin.read().rstrip("\n")
    sys.stdout.write(render(text.split("\n") if text else [], title))
