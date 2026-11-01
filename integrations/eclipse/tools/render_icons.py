#!/usr/bin/env python3
"""Draw the CoworkingView mark: serif CV, black ink, gold dot, off-white ground.

Refuses a plain red pixel. There is no separate logo file to trace.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = "/usr/share/fonts/truetype/noto/NotoSerif-Bold.ttf"
PAPER = (246, 243, 236, 255)
INK = (20, 18, 16, 255)
GOLD = (184, 148, 58, 255)


def draw(width: int, height: int) -> Image.Image:
    image = Image.new("RGBA", (width, height), PAPER)
    pen = ImageDraw.Draw(image)
    side = min(width, height)
    font = ImageFont.truetype(FONT, max(8, int(side * 0.46)))
    text = "CV"
    box = pen.textbbox((0, 0), text, font=font)
    text_width = box[2] - box[0]
    text_height = box[3] - box[1]
    x = (width - text_width) / 2 - box[0]
    y = (height - text_height) / 2 - box[1] - side * 0.04
    pen.text((x, y), text, font=font, fill=INK)
    radius = max(1, int(round(side * 0.07)))
    cx = int(width * 0.78)
    cy = int(height * 0.22)
    pen.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=GOLD)
    return image


def assert_not_red(image: Image.Image, name: str) -> None:
    raw = image.tobytes()
    for index in range(0, len(raw), 4):
        red, green, blue = raw[index], raw[index + 1], raw[index + 2]
        if red > 180 and green < 80 and blue < 80:
            raise SystemExit(f"{name} contains a red pixel {(red, green, blue)}")


def save(image: Image.Image, path: Path) -> None:
    assert_not_red(image, path.name)
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG")
    print(path)


def main() -> None:
    icons = ROOT / "com.coworkingview.eclipse" / "icons"
    docs = ROOT / "docs"
    for size in (16, 32):
        save(draw(size, size), icons / f"cv{size}.png")
    save(draw(110, 80), docs / "logo-110x80.png")
    save(draw(256, 256), docs / "logo-256.png")


if __name__ == "__main__":
    main()
