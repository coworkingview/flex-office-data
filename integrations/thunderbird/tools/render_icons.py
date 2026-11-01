#!/usr/bin/env python3
"""Draw the add-on icons: serif "CV" and a gold dot on an off-white square.

No logo file was present under /cursor/stores/bot, so this script draws the
mark itself. It refuses a pixel that is plain red.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "addon" / "icons"
FONT = "/usr/share/fonts/truetype/noto/NotoSerif-Bold.ttf"
PAPER = (246, 243, 236, 255)
INK = (20, 18, 16, 255)
GOLD = (184, 148, 58, 255)
SIZES = (16, 32, 48, 64, 96, 128)


def draw(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), PAPER)
    pen = ImageDraw.Draw(image)
    font = ImageFont.truetype(FONT, max(8, int(size * 0.46)))
    text = "CV"
    box = pen.textbbox((0, 0), text, font=font)
    width = box[2] - box[0]
    height = box[3] - box[1]
    x = (size - width) / 2 - box[0]
    y = (size - height) / 2 - box[1] - size * 0.04
    pen.text((x, y), text, font=font, fill=INK)
    radius = max(1, int(round(size * 0.07)))
    cx = int(size * 0.78)
    cy = int(size * 0.24)
    pen.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=GOLD)
    return image


def assert_not_red(image: Image.Image, name: str) -> None:
    raw = image.tobytes()
    for index in range(0, len(raw), 4):
        red, green, blue = raw[index], raw[index + 1], raw[index + 2]
        if red > 180 and green < 80 and blue < 80:
            raise SystemExit(f"{name} contains a red pixel {(red, green, blue)}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for size in SIZES:
        image = draw(size)
        assert_not_red(image, f"icon-{size}.png")
        image.save(OUT / f"icon-{size}.png", "PNG")
    print(f"wrote {len(SIZES)} icons to {OUT}")


if __name__ == "__main__":
    main()
