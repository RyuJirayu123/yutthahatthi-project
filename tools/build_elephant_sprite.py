"""Builds the elephant's animation sheets for the game from the design's action set
(ออกแบบช้างเกม Godot/assets/sheets/*.png: 880x540 frames, 4 per row, the ground at y 512 and
the feet centred at x 440 in every action; see Elephant Actions.dc.html).

    python tools/build_elephant_sprite.py

The walk and run cycles are re-cut from the source videos (VIDEOS: ออกแบบช้างเกม Godot/uploads,
24 fps) with many more frames than the design sheets, so they play smoothly: the cream
background is keyed out and each cycle is scaled and placed like its design sheet.

For each action every frame is cropped to that action's shared box (so the feet stay put),
scaled by SCALE and packed 4 per row into assets/sprites/<action>.png; the HUD portrait (the
head of the first idle frame in a soft circle) goes to assets/sprites/portrait.png.
Prints the ANIMS table for scripts/elephant_rig.gd (frame count, frame size and pivot).
"""
import pathlib

import cv2
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
UPLOADS = ROOT / "ออกแบบช้างเกม Godot" / "uploads"
## action -> [video, first frame of a seamless loop, loop length, frames to keep]
VIDEOS = {
    "walk": ["Elephant_walking_in_place_1080p_20261008001659.mp4", 39, 71, 36],
    "run": ["Elephant_running_in_place_animation_20261008153727.mp4", 102, 22, 22],
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


def key_out(bgr: np.ndarray) -> Image.Image:
    """A video frame with its flat cream background made transparent: background is the
    near-cream area reachable from the border, plus large enclosed cream holes (the curl of
    the tail); the dark outline keeps the fill out of the elephant."""
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    h, w = rgb.shape[:2]
    bg = np.median(np.concatenate([rgb[:8].reshape(-1, 3), rgb[-8:].reshape(-1, 3)]), axis=0)
    dist = np.abs(rgb.astype(np.int16) - bg.astype(np.int16)).max(axis=2)
    cand = (dist < 30).astype(np.uint8)
    n, lab, stats, _ = cv2.connectedComponentsWithStats(cand, connectivity=4)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])))
    keep = np.zeros(n, bool)
    for i in range(1, n):
        if i in border:
            keep[i] = True
        elif stats[i, cv2.CC_STAT_AREA] > 600:
            keep[i] = dist[lab == i].mean() < 8.0
    bgmask = keep[lab]
    alpha = np.where(bgmask, 0, 255).astype(np.uint8)
    # soften the cut: pixels next to the background fade by how cream they are
    near = cv2.dilate(bgmask.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    edge = near & ~bgmask
    alpha[edge] = np.clip((dist[edge] - 6) * 255 // 40, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb, alpha]))


def video_frames(name: str, design: list) -> list:
    """The action's loop cut from its video, scaled and placed to match its design frames
    (same height and ground line, same centre of mass) in CELL-sized frames."""
    video, first, length, keep = VIDEOS[name]
    cap = cv2.VideoCapture(str(UPLOADS / video))
    raw = []
    i = 0
    want = [first + round(k * length / keep) for k in range(keep)]
    while True:
        ok, bgr = cap.read()
        if not ok or i > want[-1]:
            break
        if i in want:
            raw.append(key_out(bgr))
        i += 1
    cap.release()
    assert len(raw) == keep, (name, len(raw))

    def extent(frames):
        """Top and bottom of the elephant over all frames, and its average centre of mass."""
        top, bottom, cx = 10 ** 6, 0, []
        for f in frames:
            a = np.array(f)[..., 3] > 128
            ys, xs = np.nonzero(a)
            top, bottom = min(top, ys.min()), max(bottom, ys.max())
            cx.append(xs.mean())
        return top, bottom, float(np.mean(cx))

    dt, db, dx = extent(design)
    vt, vb, vx = extent(raw)
    k = (db - dt) / (vb - vt)
    out = []
    for f in raw:
        sf = shrink(f, (round(f.width * k), round(f.height * k)))
        cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
        cell.alpha_composite(sf, (round(dx - vx * k), round(db - vb * k)))
        out.append(clean(cell))
    return out


OUT.mkdir(parents=True, exist_ok=True)
for old in OUT.glob("elephant_walk.png*"):
    old.unlink()
table = []
for name, n in ACTIONS.items():
    sheet = clean(Image.open(SHEETS / f"{name}.png").convert("RGBA"))
    frames = [sheet.crop(((i % COLS) * CELL[0], (i // COLS) * CELL[1], (i % COLS + 1) * CELL[0], (i // COLS + 1) * CELL[1])) for i in range(n)]
    if name in VIDEOS and (UPLOADS / VIDEOS[name][0]).exists():
        frames = video_frames(name, frames)
        n = len(frames)
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
