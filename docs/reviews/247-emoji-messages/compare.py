"""Compare matching renders from two checkouts. Run from the repository root."""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

before, after = map(Path, sys.argv[1:])
dest = Path(__file__).parent
for path in sorted(after.glob("*.png")):
    left, right = Image.open(before / path.name), Image.open(path)
    width, height = right.size
    comparison = Image.new("RGB", (width * 2 + 2, height + 46), "#383838")
    draw = ImageDraw.Draw(comparison)
    font = ImageFont.load_default(size=26)
    for x, label, panel in [(0, "Before", left), (width + 2, "After", right)]:
        comparison.paste(panel, (x, 46))
        draw.text((x + 18, 6), label, font=font, fill="white")
    comparison.save(dest / path.name, optimize=True)
