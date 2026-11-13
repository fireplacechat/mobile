"""Turn a folder of numbered PNG frames into an animated GIF next to it.

    python scripts/render/frames_to_gif.py build/frames/search-jump [ms]

Frames are 40 ms apart unless [ms] says otherwise (motion_frames_test.dart).
Needs Pillow. For review only; nothing here ships in the app.
"""
import pathlib
import sys

from PIL import Image


def main() -> None:
    folder = pathlib.Path(sys.argv[1])
    delay = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    frames = [Image.open(p).convert('RGB') for p in sorted(folder.glob('*.png'))]
    if not frames:
        raise SystemExit(f'No frames in {folder}')
    # Half size keeps the file small enough to share.
    frames = [f.resize((f.width // 2, f.height // 2), Image.LANCZOS) for f in frames]
    out = folder.with_suffix('.gif')
    frames[0].save(
        out,
        save_all=True,
        append_images=frames[1:],
        duration=delay,
        loop=0,
        optimize=True,
    )
    print(f'{out} ({len(frames)} frames)')


if __name__ == '__main__':
    main()
