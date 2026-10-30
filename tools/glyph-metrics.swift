// Print where glyphs sit in a font, in units of 100 per em (macOS, CoreText).
// The bars use ■ because in the fonts checked it runs from the baseline (0) to x-height (~55)
// and fills the cell (advance 60), so it lines up with the text. Lower blocks such as ▆ start
// below the baseline and hang under the text.
// Usage: swift tools/glyph-metrics.swift <font.ttf> [glyph ...]
import Foundation
import CoreText

let args = CommandLine.arguments
guard args.count > 1 else { print("usage: swift tools/glyph-metrics.swift <font.ttf> [glyph ...]"); exit(1) }
let d = (CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: args[1]) as CFURL) as! [CTFontDescriptor])[0]
let f = CTFontCreateWithFontDescriptor(d, 100, nil)
print(CTFontCopyPostScriptName(f), "x-height", Int(CTFontGetXHeight(f)), "cap", Int(CTFontGetCapHeight(f)),
      "ascent", Int(CTFontGetAscent(f)), "descent", Int(CTFontGetDescent(f)))
for s in args.count > 2 ? Array(args[2...]) : ["■", "▆", "█", "x", "H"] {
  var u = Array(s.utf16); var g = [CGGlyph](repeating: 0, count: u.count)
  guard CTFontGetGlyphsForCharacters(f, &u, &g, u.count) else { print(s, "not in font"); continue }
  let r = CTFontGetBoundingRectsForGlyphs(f, .horizontal, &g, nil, 1)
  var adv = CGSize.zero; CTFontGetAdvancesForGlyphs(f, .horizontal, &g, &adv, 1)
  print(s, "y", Int(r.minY), "to", Int(r.maxY), " x", Int(r.minX), "to", Int(r.maxX), " advance", Int(adv.width))
}
