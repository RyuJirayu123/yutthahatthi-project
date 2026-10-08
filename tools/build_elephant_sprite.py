"""Builds the elephant's animation sheets for the game from the design's action set
(ออกแบบช้างเกม Godot/assets/sheets/*.png: 880x540 frames, 4 per row, the ground at y 512 and
the feet centred at x 440 in every action; see Elephant Actions.dc.html).

    python tools/build_elephant_sprite.py

For each action every frame is cropped to that action's shared box (so the feet stay put),
scaled by SCALE and packed 4 per row into assets/sprites/<action>.png; the HUD portrait (the
head of the first idle frame in a soft circle) goes to assets/sprites/portrait.png.
Prints the ANIMS table for scripts/elephant_rig.gd (frame count, frame size and pivot).
"""
import pathlib

import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHEETS = ROOT / "ออกแบบช้างเกม Godot" / "assets" / "sheets"
OUT = ROOT / "assets" / "sprites"
CELL = (880, 540)
GROUND = (440, 512)            # the pivot in every design frame: feet centre, on the ground
COLS = 4
SCALE = 0.6
ACTIONS = {                    # frames in the design sheet
    "idle": 12, "walk": 12, "run": 12, "guard": 12, "attack_tusk": 12,
    "attack_trunk": 16, "charge": 16, "hit": 12, "victory": 16, "death": 16,
}
HEAD = (650, 150, 125)         # portrait circle in the first idle frame: centre x, y, radius
PORTRAIT = 256
INK = (46, 32, 28)             # the art's outline colour


def shrink(img: Image.Image, size: tuple) -> Image.Image:
    """Resize with premultiplied alpha, so edges don't pick up the black of empty pixels."""
    return img.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")


def clean(img: Image.Image) -> Image.Image:
    """The cut-out edge still carries the video's cream background: paint the outermost pixel
    ring (and any half-transparent pixel) the colour of the dark outline just inside it."""
    px = np.array(img)
    solid = px[..., 3] > 200
    inner = np.array(Image.fromarray((solid * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))) > 0
    px[(px[..., 3] > 0) & ~inner, :3] = INK
    return Image.fromarray(px)


OUT.mkdir(parents=True, exist_ok=True)
for old in OUT.glob("elephant_walk.png*"):
    old.unlink()
table = []
for name, n in ACTIONS.items():
    sheet = clean(Image.open(SHEETS / f"{name}.png").convert("RGBA"))
    frames = [sheet.crop(((i % COLS) * CELL[0], (i // COLS) * CELL[1], (i % COLS + 1) * CELL[0], (i // COLS + 1) * CELL[1])) for i in range(n)]
    box = None
    for f in frames:
        ys, xs = np.nonzero(np.array(f)[..., 3] > 0)
        b = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    box = (max(0, box[0] - 2), max(0, box[1] - 2), min(CELL[0], box[2] + 2), min(CELL[1], box[3] + 2))
    tw, th = round((box[2] - box[0]) * SCALE), round((box[3] - box[1]) * SCALE)
    rows = (n + COLS - 1) // COLS
    atlas = Image.new("RGBA", (tw * COLS, th * rows), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        atlas.paste(shrink(f.crop(box), (tw, th)), ((i % COLS) * tw, (i // COLS) * th))
    atlas.save(OUT / f"{name}.png", optimize=True)
    pivot = ((GROUND[0] - box[0]) * SCALE, (GROUND[1] - box[1]) * SCALE)
    table.append('\t"%s": [%d, Vector2(%d, %d), Vector2(%.1f, %.1f)],' % (name, n, tw, th, pivot[0], pivot[1]))
    print("wrote", (OUT / f"{name}.png").relative_to(ROOT), atlas.size)

# portrait: the head of the first idle frame, faded out at the rim of a circle
idle = clean(Image.open(SHEETS / "idle.png").convert("RGBA")).crop((0, 0) + CELL)
cx, cy, r = HEAD
head = np.array(idle.crop((cx - r, cy - r, cx + r, cy + r))).astype(np.float32)
yy, xx = np.mgrid[0:2 * r, 0:2 * r]
head[..., 3] *= np.clip((1.0 - np.hypot(xx - r + 0.5, yy - r + 0.5) / r) / 0.06, 0.0, 1.0)
shrink(Image.fromarray(head.astype(np.uint8)), (PORTRAIT, PORTRAIT)).save(OUT / "portrait.png", optimize=True)
print("wrote assets/sprites/portrait.png")
print("const ANIMS := {   ## action -> [frames, frame size, pivot in the frame]")
print("\n".join(table))
print("}")
