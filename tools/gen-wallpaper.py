#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tools/gen-wallpaper.py

Generate a static 1920x1080 FORGE-themed dot-grid wallpaper as a PNG and
write it to ``airootfs/etc/skel/.config/hypr/wallpaper.png`` (the path
referenced by ``hyprpaper.conf``).

Design:
  - dark canvas (#0d0e10) with a fine #1e2020 grid line every 40 px
  - amber (#f59e0b) accent dots at every 5th grid intersection, with a
    bias gradient that makes them brighter toward the upper-right corner
  - a faint hex "⬡ FORGE" wordmark in the lower-right corner

The script prefers Pillow when available (anti-aliased rendering) but
falls back to a pure-stdlib implementation that emits a fully valid PNG
using `zlib` + manual chunk encoding, so it runs on a fresh Arch system
without `python-pillow` installed.

Usage:
    python tools/gen-wallpaper.py
    python tools/gen-wallpaper.py --output ~/.config/hypr/wallpaper.png
    python tools/gen-wallpaper.py --width 3840 --height 2160
"""
from __future__ import annotations

import argparse
import os
import struct
import sys
import zlib
from pathlib import Path

# ----------------------------------------------------------------------------
# Palette
# ----------------------------------------------------------------------------
BG          = (0x0d, 0x0e, 0x10)
GRID_FAINT  = (0x1e, 0x20, 0x20)
GRID_BOLD   = (0x26, 0x29, 0x2f)
AMBER       = (0xf5, 0x9e, 0x0b)
AMBER_SOFT  = (0xf9, 0x73, 0x16)
GREEN       = (0x22, 0xc5, 0x5e)
MUTED       = (0x94, 0xa3, 0xb8)
FG          = (0xe8, 0xe6, 0xdf)

# ----------------------------------------------------------------------------
# Defaults
# ----------------------------------------------------------------------------
DEFAULT_OUT = (
    Path(__file__).resolve().parent.parent
    / "airootfs" / "etc" / "skel" / ".config" / "hypr" / "wallpaper.png"
)


# ----------------------------------------------------------------------------
# Pillow fast path
# ----------------------------------------------------------------------------
def render_with_pillow(width: int, height: int, output: Path) -> None:
    from PIL import Image, ImageDraw, ImageFont

    img  = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(img, "RGBA")

    spacing       = 40
    accent_period = 5
    diag_max      = (width ** 2 + height ** 2) ** 0.5

    # Pre-multiply alpha so the gradient is exactly visible without HSV math.
    for y in range(0, height + 1, spacing):
        draw.line([(0, y), (width, y)], fill=GRID_FAINT, width=1)
    for x in range(0, width + 1, spacing):
        draw.line([(x, 0), (x, height)], fill=GRID_FAINT, width=1)

    # Heavier grid every 5th line.
    for y in range(0, height + 1, spacing * accent_period):
        draw.line([(0, y), (width, y)], fill=GRID_BOLD, width=1)
    for x in range(0, width + 1, spacing * accent_period):
        draw.line([(x, 0), (x, height)], fill=GRID_BOLD, width=1)

    # Accent dots.
    for iy, y in enumerate(range(0, height + 1, spacing)):
        for ix, x in enumerate(range(0, width + 1, spacing)):
            if iy % accent_period != 0 or ix % accent_period != 0:
                continue
            # gradient strength -- brighter toward upper-right
            distance = ((width - x) ** 2 + y ** 2) ** 0.5
            t        = 1.0 - (distance / diag_max)
            alpha    = max(0, min(255, int(60 + 195 * t)))

            r = 2 + int(2 * t)
            draw.ellipse(
                (x - r, y - r, x + r, y + r),
                fill=AMBER + (alpha,),
            )

    # One slightly larger green dot in the upper-right -- the "forge spark".
    spark_x = int(width * 0.78)
    spark_y = int(height * 0.18)
    draw.ellipse(
        (spark_x - 16, spark_y - 16, spark_x + 16, spark_y + 16),
        fill=GREEN + (60,),
    )
    draw.ellipse(
        (spark_x - 4, spark_y - 4, spark_x + 4, spark_y + 4),
        fill=GREEN + (255,),
    )

    # Wordmark.
    text = "⬡ FORGE"
    font = None
    for path in (
        "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf",
        "/usr/share/fonts/jetbrains-mono-nerd/JetBrainsMonoNerdFont-Bold.ttf",
        "/usr/share/fonts/TTF/DejaVuSansMono-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
    ):
        if Path(path).is_file():
            try:
                font = ImageFont.truetype(path, size=42)
                break
            except OSError:
                pass
    if font is None:
        font = ImageFont.load_default()

    bbox = draw.textbbox((0, 0), text, font=font)
    tw   = bbox[2] - bbox[0]
    th   = bbox[3] - bbox[1]
    pad  = 48
    draw.text(
        (width - tw - pad, height - th - pad),
        text,
        fill=AMBER_SOFT + (220,),
        font=font,
    )

    img.save(output, format="PNG", optimize=True)


# ----------------------------------------------------------------------------
# Pure-stdlib fallback PNG encoder
# ----------------------------------------------------------------------------
def _png_chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def render_with_stdlib(width: int, height: int, output: Path) -> None:
    spacing       = 40
    accent_period = 5
    diag_max      = (width ** 2 + height ** 2) ** 0.5

    # Pre-fill background row.
    bg_row = bytes(BG) * width

    # Build the framebuffer one row at a time -- O(width*height) bytes total.
    rows = []
    for y in range(height):
        row = bytearray(bg_row)

        # Grid lines: faint every `spacing`, bold every 5*spacing.
        if y % spacing == 0:
            colour = GRID_BOLD if y % (spacing * accent_period) == 0 else GRID_FAINT
            for x in range(width):
                row[x * 3 + 0] = colour[0]
                row[x * 3 + 1] = colour[1]
                row[x * 3 + 2] = colour[2]
        else:
            # Vertical grid lines on every row.
            for x in range(0, width, spacing):
                colour = GRID_BOLD if x % (spacing * accent_period) == 0 else GRID_FAINT
                row[x * 3 + 0] = colour[0]
                row[x * 3 + 1] = colour[1]
                row[x * 3 + 2] = colour[2]

        # Amber dots at the 5x5 intersections.
        if y % (spacing * accent_period) == 0:
            for x in range(0, width, spacing * accent_period):
                distance = ((width - x) ** 2 + y ** 2) ** 0.5
                t        = 1.0 - (distance / diag_max)
                # Brightness modulates between BG (no dot) and AMBER.
                br = max(0.25, min(1.0, t * 1.4))
                r  = int(BG[0] + (AMBER[0] - BG[0]) * br)
                g  = int(BG[1] + (AMBER[1] - BG[1]) * br)
                b  = int(BG[2] + (AMBER[2] - BG[2]) * br)
                # 3x3 block centred on (x, y).
                for dy in (-1, 0, 1):
                    ry = y + dy
                    if 0 <= ry < height and dy == 0:
                        for dx in (-2, -1, 0, 1, 2):
                            rx = x + dx
                            if 0 <= rx < width:
                                row[rx * 3 + 0] = r
                                row[rx * 3 + 1] = g
                                row[rx * 3 + 2] = b
                    elif 0 <= ry < height:
                        for dx in (-1, 0, 1):
                            rx = x + dx
                            if 0 <= rx < width:
                                row[rx * 3 + 0] = r
                                row[rx * 3 + 1] = g
                                row[rx * 3 + 2] = b

        # Green spark.
        spark_x = int(width * 0.78)
        spark_y = int(height * 0.18)
        if abs(y - spark_y) <= 4:
            for x in range(max(0, spark_x - 4), min(width, spark_x + 5)):
                row[x * 3 + 0] = GREEN[0]
                row[x * 3 + 1] = GREEN[1]
                row[x * 3 + 2] = GREEN[2]

        # PNG scanlines are prefixed with a filter byte (0 = none).
        rows.append(b"\x00" + bytes(row))

    raw = b"".join(rows)
    compressed = zlib.compress(raw, 9)

    ihdr = struct.pack(
        ">IIBBBBB",
        width, height,
        8,          # bit depth
        2,          # colour type: truecolor (RGB)
        0, 0, 0,    # compression / filter / interlace
    )

    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(_png_chunk(b"IHDR", ihdr))
        fh.write(_png_chunk(b"IDAT", compressed))
        fh.write(_png_chunk(b"IEND", b""))


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------
def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate the FORGE Linux dark dot-grid wallpaper.",
    )
    parser.add_argument("--width",  type=int, default=1920)
    parser.add_argument("--height", type=int, default=1080)
    parser.add_argument(
        "--output", "-o",
        type=Path, default=DEFAULT_OUT,
        help=f"Output path (default: {DEFAULT_OUT})",
    )
    parser.add_argument(
        "--no-pillow", action="store_true",
        help="Force the pure-stdlib renderer (skip Pillow even if installed)",
    )
    args = parser.parse_args(argv)

    args.output.parent.mkdir(parents=True, exist_ok=True)

    use_pillow = not args.no_pillow
    if use_pillow:
        try:
            import PIL  # noqa: F401
        except ModuleNotFoundError:
            use_pillow = False

    if use_pillow:
        print(f"[gen-wallpaper] rendering with Pillow -> {args.output}")
        render_with_pillow(args.width, args.height, args.output)
    else:
        print(f"[gen-wallpaper] rendering with stdlib  -> {args.output}")
        render_with_stdlib(args.width, args.height, args.output)

    sz = args.output.stat().st_size
    print(f"[gen-wallpaper] wrote {sz:,} bytes  ({args.width}x{args.height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
