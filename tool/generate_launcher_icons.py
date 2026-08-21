#!/usr/bin/env python3
"""Render the legacy launcher PNGs from the adaptive icon's vector drawable.

Android draws the adaptive icon on API 26 and above, but below that it falls
back to `mipmap-*/ic_launcher.png`. Those shipped as Flutter's default logo
for the whole life of the project, so on an older phone Van was not Van.

Rendering them here rather than exporting from a design tool keeps one source
of truth: `ic_launcher_foreground.xml` is the mark, and this reproduces it.
Edit the vector, re-run this, commit the PNGs.

    python tool/generate_launcher_icons.py

Stdlib only, matching tool/generate_drum.py - a build that needs Pillow
installed to produce an icon is a build that will break on someone else's
machine.
"""

from __future__ import annotations

import re
import struct
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
RES = Path(__file__).resolve().parent.parent / "android/app/src/main/res"
FOREGROUND = RES / "drawable/ic_launcher_foreground.xml"
COLORS = RES / "values/colors.xml"

# The adaptive canvas is 108x108. Launchers mask it to roughly the central
# 72x72, so cropping to that is what makes the legacy icon fill its square the
# way the adaptive one appears to.
CANVAS = 108.0
SAFE = 72.0

DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# Samples per axis inside each output pixel. Four is plenty for shapes this
# simple and keeps the whole run well under a second.
SUPERSAMPLE = 4


def parse_hex(colour: str) -> tuple[int, int, int]:
    """Reads #RRGGBB or #AARRGGBB, ignoring any alpha."""
    digits = colour.lstrip("#")
    if len(digits) == 8:
        digits = digits[2:]
    if len(digits) != 6:
        raise ValueError(f"unsupported colour: {colour}")
    return tuple(int(digits[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def background_colour() -> tuple[int, int, int]:
    root = ET.parse(COLORS).getroot()
    for node in root.findall("color"):
        if node.get("name") == "ic_launcher_background":
            return parse_hex((node.text or "").strip())
    raise SystemExit("colors.xml has no ic_launcher_background")


_NUMBER = re.compile(r"-?\d+(?:\.\d+)?")


def numbers(text: str) -> list[float]:
    return [float(m.group()) for m in _NUMBER.finditer(text)]


class Circle:
    def __init__(self, cx: float, cy: float, r: float, colour) -> None:
        self.cx, self.cy, self.r, self.colour = cx, cy, r, colour

    def covers(self, x: float, y: float) -> bool:
        return (x - self.cx) ** 2 + (y - self.cy) ** 2 <= self.r**2


class Polygon:
    def __init__(self, points: list[tuple[float, float]], colour) -> None:
        self.points, self.colour = points, colour

    def covers(self, x: float, y: float) -> bool:
        inside = False
        n = len(self.points)
        for i in range(n):
            x1, y1 = self.points[i]
            x2, y2 = self.points[(i + 1) % n]
            if (y1 > y) != (y2 > y):
                crossing = x1 + (y - y1) / (y2 - y1) * (x2 - x1)
                if x < crossing:
                    inside = not inside
        return inside


def parse_path(data: str, colour) -> Circle | Polygon:
    """Handles the two path forms the drawable actually uses.

    Deliberately narrow. A general SVG path parser would be a lot of code to
    maintain for one icon, and anything it silently mis-rendered would ship as
    a wrong app icon. This raises instead.
    """
    # The circle idiom: "M cx,cy m-r,0 a r,r 0 1,0 2r,0 a r,r 0 1,0 -2r,0 Z".
    if " a" in data or data.count("a") and "m-" in data.replace(" ", ""):
        values = numbers(data)
        cx, cy, r = values[0], values[1], abs(values[2])
        return Circle(cx, cy, r, colour)

    commands = re.findall(r"[MLZmlz][^MLZmlz]*", data)
    points: list[tuple[float, float]] = []
    for command in commands:
        kind, rest = command[0], command[1:]
        if kind in "Zz":
            continue
        if kind not in "ML":
            raise ValueError(f"unsupported path command {kind!r} in {data!r}")
        values = numbers(rest)
        for i in range(0, len(values), 2):
            points.append((values[i], values[i + 1]))
    if len(points) < 3:
        raise ValueError(f"not a polygon: {data!r}")
    return Polygon(points, colour)


def load_shapes() -> list[Circle | Polygon]:
    root = ET.parse(FOREGROUND).getroot()
    shapes = []
    for node in root.findall("path"):
        colour = parse_hex(node.get(f"{ANDROID_NS}fillColor", "#000000"))
        shapes.append(parse_path(node.get(f"{ANDROID_NS}pathData", ""), colour))
    if not shapes:
        raise SystemExit(f"{FOREGROUND} has no paths")
    return shapes


def render(size: int, shapes, background) -> bytes:
    """Rasterises the safe-zone crop at [size]x[size], as raw RGB rows."""
    inset = (CANVAS - SAFE) / 2  # 18: the crop's top-left in canvas units.
    step = SAFE / (size * SUPERSAMPLE)
    rows = bytearray()

    for py in range(size):
        rows.append(0)  # PNG filter byte: none.
        for px in range(size):
            r = g = b = 0
            for sy in range(SUPERSAMPLE):
                y = inset + ((py * SUPERSAMPLE) + sy + 0.5) * step
                for sx in range(SUPERSAMPLE):
                    x = inset + ((px * SUPERSAMPLE) + sx + 0.5) * step
                    colour = background
                    # Painter's order: later paths sit on top, as in the vector.
                    for shape in shapes:
                        if shape.covers(x, y):
                            colour = shape.colour
                    r += colour[0]
                    g += colour[1]
                    b += colour[2]
            total = SUPERSAMPLE * SUPERSAMPLE
            rows += bytes((r // total, g // total, b // total))
    return bytes(rows)


def write_png(path: Path, size: int, raw: bytes) -> None:
    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main() -> None:
    background = background_colour()
    shapes = load_shapes()
    print(f"{len(shapes)} shapes on #{'%02X%02X%02X' % background}")

    for density, size in DENSITIES.items():
        target = RES / f"mipmap-{density}/ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        write_png(target, size, render(size, shapes, background))
        print(f"  {target.relative_to(RES.parent)}  {size}x{size}")


if __name__ == "__main__":
    main()
