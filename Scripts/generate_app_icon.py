#!/usr/bin/env python3
"""Regenerate the opaque 1024x1024 Game Crate icon (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw

S = 1024
im = Image.new("RGB", (S, S), "#142635")
d = ImageDraw.Draw(im)
d.rounded_rectangle((108, 115, 916, 910), radius=200, fill="#193C4A")
d.rounded_rectangle((212, 369, 812, 772), radius=43, fill="#E7A44A")
d.polygon([(212, 408), (512, 268), (812, 408), (512, 547)], fill="#F7CA79")
d.line([(212, 408), (512, 547), (812, 408)], fill="#163946", width=18, joint="curve")
d.line([(512, 547), (512, 775)], fill="#163946", width=18)
d.rounded_rectangle((430, 319, 594, 483), radius=29, fill="#FCF7E9", outline="#163946", width=12)
for x, y in [(470, 360), (552, 360), (511, 401), (470, 442), (552, 442)]:
    d.ellipse((x-12, y-12, x+12, y+12), fill="#163946")
im.save(Path(__file__).resolve().parents[1] / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png", optimize=True)
