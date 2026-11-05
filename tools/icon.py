"""Draws Daybreak's icon, icon.png: the README's sunset over the sea, cropped square on the sun,
with the name across the water, the way the big shader packs show theirs (a scene of the pack and
its name). 512 x 512, under the registry's 256 KiB.

    python tools/icon.py pack/daybreak/icon.png

Needs Pillow. The lettering is Bahnschrift Bold Condensed, which ships with Windows; pass another
font with --font on other systems.
"""

import argparse
import io
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs" / "screenshots" / "sunset.jpg"
FONT = "C:/Windows/Fonts/bahnschrift.ttf"
WORK, OUT = 1024, 512
MAX_BYTES = 256 * 1024

# Where the square sits in the 1920 x 1080 screenshot: centred on the sun, the sand at the
# bottom edge left out.
SUN_X, TOP, SIDE = 952, 40, 960
NIGHT = (8, 10, 30)
GOLD = (255, 200, 130)


def scene():
    im = Image.open(SOURCE).convert("RGB")
    im = im.crop((SUN_X - SIDE // 2, TOP, SUN_X + SIDE // 2, TOP + SIDE))
    im = ImageEnhance.Color(im.resize((WORK, WORK), Image.LANCZOS)).enhance(1.12)
    dark = Image.new("RGB", im.size, NIGHT)
    # The water darkens towards the bottom, so the name reads on it.
    band = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(band)
    for y in range(WORK):
        t = max(0.0, (y - WORK * 0.55) / (WORK * 0.45))
        d.line([(0, y), (WORK, y)], fill=int(150 * t**1.3))
    im = Image.composite(dark, im, band)
    # A soft vignette keeps the eye on the sun.
    vignette = Image.new("L", im.size, 0)
    ImageDraw.Draw(vignette).ellipse(
        (-WORK * 0.25, -WORK * 0.25, WORK * 1.25, WORK * 1.25), fill=255
    )
    vignette = vignette.filter(ImageFilter.GaussianBlur(WORK * 0.12))
    return Image.composite(im, dark, vignette.point(lambda v: 80 + v * 175 // 255))


def wordmark(im, font_path, word="DAYBREAK", size=230, baseline=860, tracking=0.07):
    font = ImageFont.truetype(font_path, size)
    try:
        font.set_variation_by_name(b"Bold Condensed")
    except (OSError, ValueError):
        pass  # not a variable font: use it as it is
    width = sum(font.getlength(c) for c in word) + tracking * size * (len(word) - 1)
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x = (WORK - width) / 2
    for c in word:
        d.text((x, baseline), c, font=font, fill=(255, 255, 255, 255), anchor="ls")
        x += font.getlength(c) + tracking * size
    # A gold line under the name: the first light on the horizon.
    y = baseline + size * 0.16
    d.rectangle(((WORK - width) / 2, y, (WORK + width) / 2, y + size * 0.06), fill=GOLD + (255,))
    shadow = layer.split()[3].filter(ImageFilter.GaussianBlur(size * 0.12))
    im.paste((0, 0, 20), (0, 0), shadow.point(lambda v: v * 170 // 255))
    im.paste(layer, (0, 0), layer)
    return im


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("out", nargs="?", default="icon.png")
    p.add_argument("--font", default=FONT)
    args = p.parse_args()
    icon = wordmark(scene(), args.font).resize((OUT, OUT), Image.LANCZOS)
    data = io.BytesIO()
    icon.save(data, "PNG", optimize=True)
    if data.tell() > MAX_BYTES:
        raise SystemExit(f"icon is {data.tell() >> 10} KiB, over the registry's 256 KiB")
    Path(args.out).write_bytes(data.getvalue())
    print(f"{args.out}: {OUT} x {OUT}, {data.tell() >> 10} KiB")


if __name__ == "__main__":
    main()
