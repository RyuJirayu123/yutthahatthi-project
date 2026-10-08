"""Builds assets/sprites/elephant_walk.png, the elephant drawn in fights, from the design's
12-frame walk sheet (ออกแบบช้างเกม Godot/assets/elephant-walk-sheet.png, 4 x 3 frames).

    python tools/build_elephant_sprite.py

Every frame is cropped to the same box (so the feet stay put), scaled by SCALE and packed
4 x 3; under the frames sits the HUD portrait: the head of frame IDLE in a soft circle.
Prints the numbers ElephantRig needs (frame size, pivot between the feet, portrait size).
"""
import pathlib

import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHEET = ROOT / "ออกแบบช้างเกม Godot" / "assets" / "elephant-walk-sheet.png"
OUT = ROOT / "assets" / "sprites" / "elephant_walk.png"
COLS, ROWS = 4, 3
SCALE = 0.75
IDLE = 4                      # frame used standing still: all four feet planted
HEAD = (540, 185, 135)        # portrait circle in sheet-frame pixels: centre x, y, radius
PORTRAIT = 256
INK = (46, 32, 28)            # the art's outline colour


def shrink(img: Image.Image, size: tuple) -> Image.Image:
    """Resize with premultiplied alpha, so edges don't pick up the black of empty pixels."""
    return img.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")


sheet = Image.open(SHEET).convert("RGBA")
# the cut-out edge still carries the video's cream background: paint the outermost pixel ring
# (and any half-transparent pixel) the colour of the dark outline just inside it
px = np.array(sheet)
solid = px[..., 3] > 200
inner = np.array(Image.fromarray((solid * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))) > 0
edge = (px[..., 3] > 0) & ~inner
px[edge, :3] = INK
sheet = Image.fromarray(px)
fw, fh = sheet.width // COLS, sheet.height // ROWS
frames = [sheet.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh)) for r in range(ROWS) for c in range(COLS)]

# shared crop box and the pivot (between the feet, on the ground) over all frames
box = None
foot_x = []
for f in frames:
    a = np.array(f)[..., 3] > 128
    ys, xs = np.nonzero(a)
    b = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    feet = a[int(fh * 0.85):]
    foot_x.append(np.nonzero(feet)[1].mean())
box = (max(0, box[0] - 4), max(0, box[1] - 4), min(fw, box[2] + 4), min(fh, box[3] + 4))
cw, ch = box[2] - box[0], box[3] - box[1]
tw, th = round(cw * SCALE), round(ch * SCALE)
pivot = ((float(np.mean(foot_x)) - box[0]) * SCALE, (box[3] - 4 - box[1]) * SCALE)

atlas = Image.new("RGBA", (tw * COLS, th * ROWS + PORTRAIT), (0, 0, 0, 0))
for i, f in enumerate(frames):
    atlas.paste(shrink(f.crop(box), (tw, th)), ((i % COLS) * tw, (i // COLS) * th))

# portrait: the head of the idle frame, faded out at the rim of a circle
cx, cy, r = HEAD
head = frames[IDLE].crop((cx - r, cy - r, cx + r, cy + r))
yy, xx = np.mgrid[0:2 * r, 0:2 * r]
d = np.hypot(xx - r + 0.5, yy - r + 0.5) / r
fade = np.clip((1.0 - d) / 0.06, 0.0, 1.0)
px = np.array(head).astype(np.float32)
px[..., 3] *= fade
atlas.paste(shrink(Image.fromarray(px.astype(np.uint8)), (PORTRAIT, PORTRAIT)), (0, th * ROWS))

OUT.parent.mkdir(parents=True, exist_ok=True)
atlas.save(OUT, optimize=True)
print("wrote", OUT.relative_to(ROOT), atlas.size)
print("FRAME := Vector2(%d, %d)" % (tw, th))
print("PIVOT := Vector2(%.1f, %.1f)" % pivot)
print("PORTRAIT_Y := %d" % (th * ROWS))
