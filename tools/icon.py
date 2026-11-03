"""Draws Daybreak's icon, icon.png: a 32 x 32 pixel-art sunrise over a grass block, scaled to
256 x 256. No dependencies: the PNG is written by hand.

    python tools/icon.py pack/daybreak/icon.png
"""

import struct
import sys
import zlib

SIZE, SCALE = 32, 8
HORIZON = 20


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def noise(x, y):
    """A fixed value 0..1 per pixel, for the texture of grass and dirt."""
    h = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h & 0xFF) / 255


def pixel(x, y):
    if y < HORIZON:
        # Sky: deep blue overhead to warm orange at the horizon.
        t = y / (HORIZON - 1)
        sky = mix((28, 52, 128), (120, 110, 170), min(t * 1.6, 1.0))
        sky = mix(sky, (250, 146, 72), max(t - 0.45, 0.0) / 0.55)
        # The sun, half risen, with a glow around it.
        d = ((x - 15.5) ** 2 + (y - HORIZON + 0.5) ** 2) ** 0.5
        if d < 6.5:
            return mix((255, 246, 214), (255, 204, 96), d / 6.5)
        glow = max(0.0, 1.0 - (d - 6.5) / 7.0)
        return mix(sky, (255, 196, 120), glow * 0.6)
    n = noise(x, y)
    if y < HORIZON + 3 or (y == HORIZON + 3 and n > 0.5):
        # Grass, lit warm by the low sun.
        return mix((86, 150, 52), (128, 186, 70), n)
    return mix((104, 70, 44), (146, 102, 64), n)


def png(rows, width, height):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rows)
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main(path):
    small = [[pixel(x, y) for x in range(SIZE)] for y in range(SIZE)]
    rows = [
        [small[y // SCALE][x // SCALE] for x in range(SIZE * SCALE)]
        for y in range(SIZE * SCALE)
    ]
    with open(path, "wb") as f:
        f.write(png(rows, SIZE * SCALE, SIZE * SCALE))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "icon.png")
