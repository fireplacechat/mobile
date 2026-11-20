"""Compare matching renders from two checkouts. Run from the repository root."""
import sys
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

before, after = map(Path, sys.argv[1:])
dest = Path(__file__).parent
def compare(path):
    left, right = Image.open(before / path.relative_to(after)), Image.open(path)
    width, height = right.size
    comparison = Image.new("RGB", (width * 2 + 2, height + 46), "#383838")
    draw = ImageDraw.Draw(comparison)
    font = ImageFont.load_default(size=26)
    for x, label, panel in [(0, "Before", left), (width + 2, "After", right)]:
        comparison.paste(panel, (x, 46))
        draw.text((x + 18, 6), label, font=font, fill="white")
    return comparison


for path in sorted(after.glob("*.png")):
    compare(path).save(dest / path.name, optimize=True)

for folder in sorted(after.glob("hold-*")):
    frames = Path("build/emoji-comparisons") / folder.name
    frames.mkdir(parents=True, exist_ok=True)
    for path in sorted(folder.glob("*.png")):
        compare(path).save(frames / path.name)
    subprocess.run([sys.executable, "scripts/render/frames_to_gif.py", str(frames), "100"], check=True)
    (dest / (folder.name + ".gif")).write_bytes(frames.with_suffix(".gif").read_bytes())
