#!/usr/bin/env python3
"""Draw the app icon: serif "CV" and a gold dot on an off-white tile.

The mark is the CoworkingView wordmark reduced to two letters. Paths come
from Noto Serif Bold so the icon does not depend on a font at runtime.
"""

from __future__ import annotations

import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "com.coworkingview.Rates.svg"
FONT = Path("/usr/share/fonts/truetype/noto/NotoSerif-Bold.ttf")
PAPER = "#F6F3EC"
INK = "#141210"
GOLD = "#B8943A"


def _reject_red(color: str) -> None:
    red = int(color[1:3], 16)
    green = int(color[3:5], 16)
    blue = int(color[5:7], 16)
    if red > 180 and green < 80 and blue < 80:
        raise SystemExit(f"{color} is red")


def _glyph(font: TTFont, char: str, scale: float, x: float, baseline: float) -> tuple[str, float]:
    glyph_set = font.getGlyphSet()
    name = font.getBestCmap()[ord(char)]
    pen = SVGPathPen(glyph_set)
    transform = TransformPen(pen, (scale, 0, 0, -scale, x, baseline))
    glyph_set[name].draw(transform)
    return pen.getCommands(), glyph_set[name].width * scale


def main() -> None:
    for color in (PAPER, INK, GOLD):
        _reject_red(color)
    font = TTFont(FONT)
    scale = 62 / font["head"].unitsPerEm
    glyph_set = font.getGlyphSet()
    cmap = font.getBestCmap()
    advances = [glyph_set[cmap[ord(char)]].width * scale for char in "CV"]
    gap = 1.5
    text_width = advances[0] + gap + advances[1]
    origin_x = (128 - text_width) / 2 - 1
    baseline = 84
    letter_c, _advance_c = _glyph(font, "C", scale, origin_x, baseline)
    letter_v, _advance_v = _glyph(font, "V", scale, origin_x + advances[0] + gap, baseline)
    dot_cx = origin_x + text_width + 1
    dot_cy = 34
    svg = f"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <rect x="8" y="8" width="112" height="112" rx="26" fill="{PAPER}"/>
  <path fill="{INK}" d="{letter_c}"/>
  <path fill="{INK}" d="{letter_v}"/>
  <circle cx="{dot_cx:.1f}" cy="{dot_cy:.1f}" r="6.5" fill="{GOLD}"/>
</svg>
"""
    OUT.write_text(svg, encoding="utf-8")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    sys.exit(main())
