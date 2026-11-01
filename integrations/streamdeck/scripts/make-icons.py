#!/usr/bin/env python3
"""Build Stream Deck icons from the CoworkingView mark.

Source: integrations/nextcloud/coworkingview/img/app.png
The mark is a black serif CV with a gold dot on white. List icons are the
same mark knocked out to white on transparency. Key and plugin icons keep
the black letters and the gold dot.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parents[1] / "integrations" / "nextcloud" / "coworkingview" / "img" / "app.png"
PLUGIN = ROOT / "com.coworkingview.prices.sdPlugin"
PAPER = (247, 244, 239, 255)
WHITE_CUTOFF = 245


def knockout(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    assert pixels is not None
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0 or (red >= WHITE_CUTOFF and green >= WHITE_CUTOFF and blue >= WHITE_CUTOFF):
                pixels[x, y] = (0, 0, 0, 0)
    return image


def crop_alpha(image: Image.Image) -> Image.Image:
    bbox = image.getbbox()
    if bbox is None:
        raise SystemExit("logo has no visible pixels")
    return image.crop(bbox)


def fit(image: Image.Image, size: int, fill: float) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    target = max(1, int(size * fill))
    scale = target / max(image.size)
    resized = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.Resampling.LANCZOS)
    x = (size - resized.width) // 2
    y = (size - resized.height) // 2
    canvas.alpha_composite(resized, (x, y))
    return canvas


def to_white(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    assert pixels is not None
    for y in range(image.height):
        for x in range(image.width):
            _red, _green, _blue, alpha = pixels[x, y]
            pixels[x, y] = (255, 255, 255, alpha)
    return image


def assert_white(path: Path) -> None:
    image = Image.open(path).convert("RGBA")
    colors = {pixel[:3] for pixel in image.getdata() if pixel[3] > 0}
    if colors != {(255, 255, 255)}:
        raise SystemExit(f"{path} is not white on transparent: {colors}")


def save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG")


def paper_key(glyph: Image.Image, size: int) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), PAPER)
    # Leave the lower portion clear so the Stream Deck title stays readable.
    available = int(size * 0.58)
    scale = available / max(glyph.size)
    resized = glyph.resize(
        (max(1, round(glyph.width * scale)), max(1, round(glyph.height * scale))),
        Image.Resampling.LANCZOS,
    )
    x = (size - resized.width) // 2
    y = int(size * 0.06)
    canvas.alpha_composite(resized, (x, y))
    return canvas


def with_rule(glyph: Image.Image, size: int) -> Image.Image:
    """White CV plus a short rule, so the rate action is distinct at 20 px."""
    canvas = fit(glyph, size, 0.62)
    draw = ImageDraw.Draw(canvas)
    inset = max(2, size // 6)
    top = size - max(3, size // 5)
    thickness = max(1, size // 16)
    draw.rectangle((inset, top, size - inset, top + thickness), fill=(255, 255, 255, 255))
    return canvas


def main() -> None:
    logo = crop_alpha(knockout(Image.open(SOURCE)))
    white = to_white(logo)

    plugin_dir = PLUGIN / "imgs" / "plugin"
    save(paper_key(logo, 256), plugin_dir / "marketplace.png")
    save(paper_key(logo, 512), plugin_dir / "marketplace@2x.png")
    save(fit(white, 28, 0.78), plugin_dir / "category-icon.png")
    save(fit(white, 56, 0.78), plugin_dir / "category-icon@2x.png")

    for name, painter in (
        ("workspace-count", lambda size: fit(white, size, 0.72)),
        ("market-rate", lambda size: with_rule(white, size)),
    ):
        action = PLUGIN / "imgs" / "actions" / name
        save(painter(20), action / "icon.png")
        save(painter(40), action / "icon@2x.png")
        save(paper_key(logo, 72), action / "key.png")
        save(paper_key(logo, 144), action / "key@2x.png")

    marketplace = ROOT / "marketplace" / "app-icon-288.png"
    save(paper_key(logo, 288), marketplace)

    for path in (
        plugin_dir / "category-icon.png",
        plugin_dir / "category-icon@2x.png",
        PLUGIN / "imgs" / "actions" / "workspace-count" / "icon.png",
        PLUGIN / "imgs" / "actions" / "workspace-count" / "icon@2x.png",
        PLUGIN / "imgs" / "actions" / "market-rate" / "icon.png",
        PLUGIN / "imgs" / "actions" / "market-rate" / "icon@2x.png",
    ):
        assert_white(path)

    print(f"icons written from {SOURCE}")


if __name__ == "__main__":
    main()
