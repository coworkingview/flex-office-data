#!/usr/bin/env python3
"""Render Marketplace thumbnail and gallery images from the live public API.

The pictures are labeled renderings of neutral rounded keys. They do not draw
a branded device or use a hardware wordmark.
"""

from __future__ import annotations

import json
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "marketplace"
LOGO = ROOT.parents[1] / "integrations" / "nextcloud" / "coworkingview" / "img" / "app.png"
API = "https://api.coworkingview.com"

W, H = 1920, 960
PAPER = (247, 244, 239, 255)
INK = (28, 25, 23, 255)
MUTED = (98, 90, 82, 255)
KEY = (255, 252, 248, 255)
KEY_EDGE = (186, 178, 168, 255)
BLANK = (232, 226, 218, 255)
BLANK_EDGE = (196, 188, 178, 255)

FONT = "/usr/share/fonts/truetype/macos/Inter-Regular.ttf"
FONT_MED = "/usr/share/fonts/truetype/macos/Inter-Medium.ttf"
FONT_SEMI = "/usr/share/fonts/truetype/macos/Inter-SemiBold.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/macos/Inter-Bold.ttf"


def fetch_json(path: str) -> dict:
    request = urllib.request.Request(
        API + path,
        headers={
            "Accept": "application/json",
            "User-Agent": "coworkingview-streamdeck/1.0.0 (+https://github.com/coworkingview/flex-office-data)",
        },
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        body = json.load(response)
    if not isinstance(body, dict):
        raise SystemExit(f"unexpected payload from {path}")
    return body


def load_figures() -> dict[str, str]:
    properties = fetch_json("/v1/properties?locale=en&city=berlin&page=1&pageSize=1")
    rates = fetch_json("/v1/market/rates?locale=en&city=berlin")
    total = properties["meta"]["pagination"]["total"]
    if not isinstance(total, int) or total < 0:
        raise SystemExit("catalogue total is missing")
    city_name = "Berlin"
    rows = properties.get("data") or []
    if rows and rows[0].get("city", {}).get("slug") == "berlin":
        city_name = rows[0]["city"]["name"]

    cities = rates["data"]["cities"]
    city = next(item for item in cities if item["city"]["slug"] == "berlin")
    flex = next(figure for figure in city["figures"] if figure["optionType"] == "flex_desk")
    amount = flex["median"]["amount"]
    currency = flex["median"]["currency"]
    if not isinstance(amount, (int, float)) or not isinstance(currency, str):
        raise SystemExit("flex desk median is missing")
    amount_text = str(int(amount)) if float(amount).is_integer() else str(amount)
    return {
        "total": str(total),
        "city": city_name,
        "amount": amount_text,
        "currency": currency,
        "as_of": str(rates["data"].get("asOf") or ""),
    }


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def knockout_logo() -> Image.Image:
    image = Image.open(LOGO).convert("RGBA")
    pixels = image.load()
    assert pixels is not None
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0 or (red >= 245 and green >= 245 and blue >= 245):
                pixels[x, y] = (0, 0, 0, 0)
    bbox = image.getbbox()
    if bbox is None:
        raise SystemExit("logo has no visible pixels")
    return image.crop(bbox)


def new_canvas() -> Image.Image:
    return Image.new("RGBA", (W, H), PAPER)


def text_width(draw: ImageDraw.ImageDraw, text: str, face: ImageFont.FreeTypeFont) -> int:
    box = draw.textbbox((0, 0), text, font=face)
    return box[2] - box[0]


def draw_text(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    text: str,
    face: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int, int] = INK,
) -> None:
    draw.text(xy, text, font=face, fill=fill)


def rounded_key(
    canvas: Image.Image,
    origin: tuple[int, int],
    size: int,
    logo: Image.Image | None,
    lines: list[tuple[str, ImageFont.FreeTypeFont]],
    *,
    blank: bool = False,
) -> None:
    x0, y0 = origin
    radius = int(size * 0.16)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (x0 + 6, y0 + 10, x0 + size + 6, y0 + size + 10),
        radius=radius,
        fill=(28, 25, 23, 32),
    )
    canvas.alpha_composite(shadow)
    draw = ImageDraw.Draw(canvas)
    fill = BLANK if blank else KEY
    edge = BLANK_EDGE if blank else KEY_EDGE
    draw.rounded_rectangle((x0, y0, x0 + size, y0 + size), radius=radius, fill=fill, outline=edge, width=3)
    if blank or logo is None:
        return
    mark_width = int(size * 0.42)
    mark = logo.resize((mark_width, int(logo.height * mark_width / logo.width)), Image.Resampling.LANCZOS)
    canvas.alpha_composite(mark, (x0 + (size - mark.width) // 2, y0 + int(size * 0.10)))
    cursor = y0 + size - int(size * 0.08)
    for text, face in reversed(lines):
        box = draw.textbbox((0, 0), text, font=face)
        height = box[3] - box[1]
        cursor -= height
        draw.text((x0 + (size - (box[2] - box[0])) / 2 - box[0], cursor - box[1]), text, font=face, fill=INK)
        cursor -= int(size * 0.025)


def rendering_label(draw: ImageDraw.ImageDraw) -> None:
    face = font(FONT_SEMI, 22)
    label = "RENDERING"
    pad_x, pad_y = 16, 8
    box = draw.textbbox((0, 0), label, font=face)
    width = box[2] - box[0] + pad_x * 2
    height = box[3] - box[1] + pad_y * 2
    x, y = 72, 56
    draw.rounded_rectangle((x, y, x + width, y + height), radius=height // 2, fill=(28, 25, 23, 255))
    draw.text((x + pad_x - box[0], y + pad_y - box[1]), label, font=face, fill=(247, 244, 239, 255))


def footer(draw: ImageDraw.ImageDraw, figures: dict[str, str]) -> None:
    face = font(FONT, 24)
    as_of = figures["as_of"][:10] if figures["as_of"] else "the published index"
    line = (
        f"Rendering of key titles, not a photograph. Berlin catalogue {figures['total']}. "
        f"Flex desk median {figures['amount']} {figures['currency']}. Index as of {as_of}."
    )
    draw_text(draw, (72, H - 72), line, face, MUTED)


def count_lines(size: int) -> list[tuple[str, ImageFont.FreeTypeFont]]:
    return [
        (FIGURES["total"], font(FONT_BOLD, int(size * 0.16))),
        (FIGURES["city"], font(FONT_MED, int(size * 0.075))),
    ]


def rate_lines(size: int) -> list[tuple[str, ImageFont.FreeTypeFont]]:
    return [
        (f"{FIGURES['amount']} {FIGURES['currency']}", font(FONT_BOLD, int(size * 0.13))),
        ("Flex desk", font(FONT_MED, int(size * 0.065))),
        (FIGURES["city"], font(FONT, int(size * 0.058))),
    ]


def save(image: Image.Image, name: str) -> None:
    path = OUT / name
    image.convert("RGB").save(path, "PNG", optimize=True)
    print(path, image.size)


def render_thumbnail(logo: Image.Image) -> None:
    canvas = new_canvas()
    draw = ImageDraw.Draw(canvas)
    rendering_label(draw)
    draw_text(draw, (72, 150), "Coworking Prices", font(FONT_BOLD, 84), INK)
    draw_text(draw, (72, 258), "Berlin", font(FONT, 40), MUTED)
    draw_text(draw, (72, 340), "Workspace Count", font(FONT_SEMI, 28), INK)
    draw_text(draw, (72, 382), "Coworking spaces listed", font(FONT, 26), MUTED)
    draw_text(draw, (72, 520), "Market Rate", font(FONT_SEMI, 28), INK)
    draw_text(draw, (72, 562), "Monthly flex desk median", font(FONT, 26), MUTED)
    footer(draw, FIGURES)
    size = 430
    rounded_key(canvas, (980, 210), size, logo, count_lines(size))
    rounded_key(canvas, (1460, 210), size, logo, rate_lines(size))
    save(canvas, "thumbnail.png")


def render_key_row(logo: Image.Image) -> None:
    canvas = new_canvas()
    draw = ImageDraw.Draw(canvas)
    rendering_label(draw)
    draw_text(draw, (72, 148), "Both keys", font(FONT_BOLD, 64), INK)
    draw_text(draw, (72, 230), "Neutral key shapes. The titles are the live Berlin figures.", font(FONT, 30), MUTED)
    footer(draw, FIGURES)
    size = 250
    gap = 28
    row_width = size * 6 + gap * 5
    x = (W - row_width) // 2
    y = 360
    titles = {
        1: count_lines(size),
        2: rate_lines(size),
    }
    for index in range(6):
        lines = titles.get(index)
        rounded_key(
            canvas,
            (x + index * (size + gap), y),
            size,
            logo if lines else None,
            lines or [],
            blank=lines is None,
        )
    save(canvas, "gallery-keys.png")


def render_single(logo: Image.Image, name: str, heading: str, detail: str, lines_for) -> None:
    canvas = new_canvas()
    draw = ImageDraw.Draw(canvas)
    rendering_label(draw)
    draw_text(draw, (760, 250), heading, font(FONT_BOLD, 72), INK)
    draw_text(draw, (760, 350), detail, font(FONT, 36), MUTED)
    draw_text(draw, (760, 430), FIGURES["city"], font(FONT_SEMI, 36), INK)
    footer(draw, FIGURES)
    size = 560
    rounded_key(canvas, (120, 180), size, logo, lines_for(size))
    save(canvas, name)


FIGURES: dict[str, str] = {}


def main() -> None:
    global FIGURES
    FIGURES = load_figures()
    print(json.dumps(FIGURES, indent=2))
    logo = knockout_logo()
    OUT.mkdir(parents=True, exist_ok=True)
    render_thumbnail(logo)
    render_key_row(logo)
    render_single(
        logo,
        "gallery-workspace-count.png",
        "Workspace Count",
        "Coworking spaces listed in this city.",
        count_lines,
    )
    render_single(
        logo,
        "gallery-market-rate.png",
        "Market Rate",
        "Monthly flex desk median.",
        rate_lines,
    )


if __name__ == "__main__":
    main()
