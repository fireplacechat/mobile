"""Join the before and after frames, then use the app's review GIF encoder."""
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

before, after = map(Path, sys.argv[1:])
dest = Path(__file__).parent
for folder in sorted(after.iterdir()):
    if not folder.is_dir():
        continue
    frames = Path("build/request-comparisons") / folder.name
    frames.mkdir(parents=True, exist_ok=True)
    for src in sorted(folder.glob("*.png")):
        left = Image.open(before / folder.name / src.name)
        right = Image.open(src)
        width, height = right.size
        pair = Image.new("RGB", (width * 2 + 2, height + 48), "#343434")
        draw = ImageDraw.Draw(pair)
        for x, label, panel in [(0, "Before", left), (width + 2, "After", right)]:
            pair.paste(panel, (x, 48))
            draw.text((x + 18, 6), label, font=ImageFont.load_default(size=26), fill="white")
        pair.save(frames / src.name)
        if src.stem == "07":
            pair.save(dest / (folder.name + ".png"), optimize=True)
    subprocess.run([sys.executable, "scripts/render/frames_to_gif.py", str(frames), "190"], check=True)
    (dest / (folder.name + ".gif")).write_bytes(frames.with_suffix(".gif").read_bytes())
