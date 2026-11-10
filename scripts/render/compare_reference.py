"""Compare a render with a reference screenshot of the same pixel width.

python3 scripts/render/compare_reference.py RENDER REFERENCE OUT_PREFIX \
    [--render-top PX] [--reference-top PX] [--height PX]

Writes OUT_PREFIX-side.png (reference left, render right) and
OUT_PREFIX-overlay.png (an even blend). Reference screenshots may contain
other people's names and messages: keep them and these outputs out of Git
unless the owner has cleared them.
"""

import argparse

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("render")
    parser.add_argument("reference")
    parser.add_argument("out")
    parser.add_argument("--render-top", type=int, default=0)
    parser.add_argument("--reference-top", type=int, default=0)
    parser.add_argument("--height", type=int, default=0)
    args = parser.parse_args()
    render = Image.open(args.render).convert("RGB")
    reference = Image.open(args.reference).convert("RGB")
    if render.width != reference.width:
        raise SystemExit(
            f"widths differ: render {render.width}, reference {reference.width}"
        )
    height = args.height or min(
        render.height - args.render_top, reference.height - args.reference_top
    )
    ours = render.crop((0, args.render_top, render.width, args.render_top + height))
    theirs = reference.crop(
        (0, args.reference_top, reference.width, args.reference_top + height)
    )
    side = Image.new("RGB", (ours.width * 2 + 12, height), "white")
    side.paste(theirs, (0, 0))
    side.paste(ours, (ours.width + 12, 0))
    side.save(f"{args.out}-side.png")
    Image.blend(theirs, ours, 0.5).save(f"{args.out}-overlay.png")


if __name__ == "__main__":
    main()
