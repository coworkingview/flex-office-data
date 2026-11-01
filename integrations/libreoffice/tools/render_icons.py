"""Render extension icons from the CoworkingView mark.

The mark is the existing wordmark (CV and a gold dot on white). This crops
to that ink and scales it. It does not draw a new symbol.
"""

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "icons" / "coworkingview-mark.png"
ICON = ROOT / "icons" / "icon.png"
ICON_HC = ROOT / "icons" / "icon_hc.png"
LISTING = ROOT / "docs" / "logo-150.png"


def _ink_box(image):
    image = image.convert("RGBA")
    width, height = image.size
    min_x, min_y, max_x, max_y = width, height, 0, 0
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = image.getpixel((x, y))
            if alpha < 10 or (red > 245 and green > 245 and blue > 245):
                continue
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)
    return min_x, min_y, max_x, max_y


def _square(image):
    image = image.convert("RGBA")
    min_x, min_y, max_x, max_y = _ink_box(image)
    crop_w = max_x - min_x + 1
    crop_h = max_y - min_y + 1
    side = max(crop_w, crop_h)
    pad = int(side * 0.12)
    side = side + pad * 2
    canvas = Image.new("RGBA", (side, side), (255, 255, 255, 255))
    crop = image.crop((min_x, min_y, max_x + 1, max_y + 1))
    canvas.paste(crop, ((side - crop_w) // 2, (side - crop_h) // 2))
    return canvas


def _high_contrast(image):
    source = image.convert("RGBA")
    out = Image.new("RGBA", source.size, (0, 0, 0, 0))
    for y in range(source.size[1]):
        for x in range(source.size[0]):
            red, green, blue, alpha = source.getpixel((x, y))
            if alpha < 10 or (red > 245 and green > 245 and blue > 245):
                continue
            out.putpixel((x, y), (255, 255, 255, 255))
    return out


def main():
    if not SOURCE.is_file():
        print("missing " + str(SOURCE), file=sys.stderr)
        return 1
    square = _square(Image.open(SOURCE))
    square.resize((128, 128), Image.Resampling.LANCZOS).save(ICON)
    _high_contrast(square).resize((128, 128), Image.Resampling.LANCZOS).save(ICON_HC)
    square.resize((150, 150), Image.Resampling.LANCZOS).save(LISTING)
    print("wrote", ICON.name, ICON_HC.name, LISTING.name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
