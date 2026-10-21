# -*- coding: utf-8 -*-
"""Murloc Tac Toe's Feast of Winter Veil dress, built from the art already in Media\\.

Writes three textures beside the Hallow's End ones:

    MurlocTacToe_Board_WinterVeil.tga    1024 x 1024   the pond board, frozen over
    MurlocTacToe_Divider_WinterVeil.tga   512 x 128     a snowed garland, 94 px of it used
    MurlocTacToe_Pile_WinterVeil.tga      256 x 256     presents, 126 px of it used

The board is DERIVED from MurlocTacToe_Board.tga rather than painted: the same mossy pond, cooled
to ice, with snow laid on every surface that faces up and the nine cells glazed over. The Hallow's
End board is a painting of its own and this one is not as rich - it is meant to be replaced by one
when there is art for it, and nothing but the file has to change.

    python tools/build_winterveil_art.py            # writes into the live Media folder
    python tools/build_winterveil_art.py --out DIR  # somewhere else, to look at first

Run it from the repo root. Needs Pillow and numpy.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

LIVE_MEDIA = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothAlmanac\Media"

# the pond board's own greens, and what they become under ice
ICE_HUE = 0.56          # where the mosses and weeds end up (a cold blue)
SNOW = (236, 244, 255)  # the white that lies on top of things


def _hsv(rgb):
    """RGB float array (h, w, 3) in 0..1 -> HSV, same shape."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-6
    # the usual six sectors, guarded so a grey pixel keeps hue 0
    ri, gi, bi = (mx == r) & nz, (mx == g) & nz, (mx == b) & nz
    h[ri] = ((g - b)[ri] / d[ri]) % 6
    h[gi] = ((b - r)[gi] / d[gi]) + 2
    h[bi] = ((r - g)[bi] / d[bi]) + 4
    h /= 6.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return np.stack([h, s, mx], -1)


def _rgb(hsv):
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    i = np.floor(h * 6).astype(int)
    f = h * 6 - i
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    out = np.zeros(hsv.shape, dtype=np.float32)
    for k, (rr, gg, bb) in enumerate(((v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q))):
        m = i == k
        out[..., 0][m], out[..., 1][m], out[..., 2][m] = rr[m], gg[m], bb[m]
    return out


def _upward_faces(lum):
    """How much each pixel reads as a surface facing up, 0..1.

    Snow settles where a surface turns over towards the sky. In a painting that shows up as a
    light edge directly above a darker one, so the vertical fall-off of a blurred luminance is a
    good enough stand-in for a normal map.
    """
    blur = np.asarray(Image.fromarray((lum * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.5)),
                      dtype=np.float32) / 255.0
    below = np.roll(blur, -4, axis=0)
    below[-4:, :] = blur[-4:, :]
    fall = np.clip(blur - below, 0, None) * 6.0
    # only where there is something lit to begin with: not in the black recesses
    return np.clip(fall, 0, 1) * np.clip(blur * 1.6, 0, 1)


def freeze_board(src_path):
    im = Image.open(src_path).convert("RGBA")
    a = np.asarray(im, dtype=np.float32) / 255.0
    rgb, alpha = a[..., :3], a[..., 3]

    # Frozen reads as "almost no colour, lit cold" far more reliably than moving hues about: an
    # earlier go shifted the greens towards blue and only made the board look sickly, because the
    # mosses and the wood share a hue and the knotwork went with them. So: take nearly all the
    # colour out, then light the whole thing with a cold sky.
    hsv = _hsv(rgb)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    s = s * 0.16                                   # a trace of the old colour, no more
    v = np.clip(v ** 0.88 * 1.10, 0, 1)            # lift the midtones: snow light is flat and bright
    out = _rgb(np.stack([h, s, v], -1))

    lum = out @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    # cold light: blue in the shadows, a faint warm pink where it is brightest, as real snow does
    cold = np.array([0.62, 0.74, 0.95], dtype=np.float32)
    warm = np.array([1.00, 0.97, 0.93], dtype=np.float32)
    t = np.clip(lum, 0, 1)[..., None]
    out = out * 0.45 + (cold * (1 - t) + warm * t) * out.mean(-1, keepdims=True) * 1.55 * 0.55

    # snow on every upward face
    lum = np.clip(out, 0, 1) @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    snow = _upward_faces(lum)[..., None]
    snow_rgb = np.array(SNOW, dtype=np.float32) / 255.0
    out = out * (1 - snow) + snow_rgb * snow

    # the nine cells are the darkest places on the board: glaze them, so they read as panes of ice
    # rather than holes, but keep them dark enough for a creature to stand out against.
    dark = np.clip((0.34 - lum) / 0.34, 0, 1)[..., None]
    # dark, but dark BLUE: left to itself the recess keeps the old board's brown and reads as mud
    glaze = np.array([0.30, 0.44, 0.60], dtype=np.float32)
    out = out * (1 - dark * 0.80) + glaze * (dark * 0.80)

    # a breath of frost into the corners
    yy, xx = np.mgrid[0:im.height, 0:im.width].astype(np.float32)
    cx, cy = im.width / 2.0, im.height / 2.0
    r = np.sqrt(((xx - cx) / cx) ** 2 + ((yy - cy) / cy) ** 2)
    frost = np.clip((r - 0.74) / 0.5, 0, 1)[..., None] * 0.30
    out = out * (1 - frost) + np.array([0.86, 0.93, 1.0], dtype=np.float32) * frost

    out = np.clip(out, 0, 1)
    return Image.fromarray(np.concatenate([out, alpha[..., None]], -1).__mul__(255).astype(np.uint8), "RGBA")


def _rounded(d, box, r, fill):
    try:
        d.rounded_rectangle(box, radius=r, fill=fill)
    except AttributeError:  # very old Pillow
        d.rectangle(box, fill=fill)


def build_divider(w=512, h=128, used=94):
    """A snowed garland: a frosted rope with holly, berries and clumps of snow along it."""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    mid = used * 0.52
    # the rope: a dark evergreen swag that dips in the middle
    pts = [(x, mid + 13 * np.sin(np.pi * x / w) ** 1.4) for x in range(0, w + 1, 4)]
    for off, col in ((3, (18, 40, 26, 255)), (0, (34, 68, 44, 255)), (-2, (52, 94, 62, 255))):
        d.line([(x, y + off) for x, y in pts], fill=col, width=9 if off == 0 else 7)
    # needles, so the swag isn't a smooth tube
    rng = np.random.default_rng(7)
    for x, y in pts[::1]:
        for _ in range(3):
            ax = x + rng.uniform(-5, 5)
            ay = y + rng.uniform(-7, 7)
            d.line([(x, y), (ax, ay)], fill=(40, 78, 50, 255), width=2)
    # holly leaves and red berries at intervals
    for i in range(1, 8):
        x = w * i / 8.0
        y = mid + 13 * np.sin(np.pi * x / w) ** 1.4
        for s in (-1, 1):
            d.polygon([(x, y - 2), (x + s * 13, y - 10), (x + s * 19, y + 1), (x + s * 9, y + 8)],
                      fill=(30, 92, 46, 255), outline=(16, 56, 28, 255))
        for bx, by in ((-4, 4), (3, 6), (0, -2)):
            d.ellipse([x + bx - 3, y + by - 3, x + bx + 3, y + by + 3], fill=(176, 32, 36, 255))
    # snow lying along the top of it all
    for x, y in pts:
        rr = 4 + 2.4 * np.sin(x * 0.11)
        d.ellipse([x - rr, y - 8 - rr * 0.5, x + rr, y - 8 + rr * 0.5], fill=SNOW + (255,))
    im = im.filter(ImageFilter.SMOOTH)
    # the ends fade out, so the garland doesn't stop dead at the board's edge
    a = np.asarray(im, dtype=np.float32)
    xs = np.linspace(0, 1, w, dtype=np.float32)
    fade = np.clip(np.minimum(xs, 1 - xs) / 0.08, 0, 1)[None, :]
    a[..., 3] *= fade
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def build_pile(size=256, used=126):
    """A little heap of wrapped presents, to stand where the pumpkins do at Hallow's End."""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    base = used - 26   # (everything, drift included, has to fit inside the `used` rows the game crops to)
    # the drift goes down FIRST and the presents sit in front of it; drawing it over them and then
    # redrawing them cost the bows, which is how the first go lost them.
    d.ellipse([-6, base - 6, size + 6, base + 18], fill=SNOW + (255,))
    # (x, y, w, h, paper, ribbon) - back row first, so the front row overlaps it
    boxes = [
        (18, base - 52, 54, 48, (46, 92, 58), (226, 206, 120)),
        (150, base - 60, 60, 56, (142, 44, 50), (236, 228, 180)),
        (2, base - 30, 44, 28, (150, 86, 142), (240, 236, 210)),
        (76, base - 44, 64, 42, (58, 78, 136), (226, 206, 120)),
        (196, base - 34, 50, 32, (56, 104, 96), (226, 206, 120)),
    ]
    for x, y, w, h, paper, ribbon in boxes:
        _rounded(d, [x, y, x + w, y + h], 4, paper + (255,))
        # a lit lid and a shaded right side, so a box isn't a flat rectangle
        d.rectangle([x, y, x + w, y + 7], fill=tuple(min(255, c + 36) for c in paper) + (255,))
        d.rectangle([x + w - 9, y, x + w, y + h], fill=tuple(int(c * 0.70) for c in paper) + (255,))
        # ribbon, across and up
        d.rectangle([x + w * 0.42, y, x + w * 0.58, y + h], fill=ribbon + (255,))
        d.rectangle([x, y + h * 0.46, x + w, y + h * 0.62], fill=ribbon + (255,))
        # the bow on top
        cx, cy = x + w * 0.5, y + 1
        d.ellipse([cx - 12, cy - 8, cx - 1, cy + 3], fill=ribbon + (255,))
        d.ellipse([cx + 1, cy - 8, cx + 12, cy + 3], fill=ribbon + (255,))
        d.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=tuple(int(c * 0.8) for c in ribbon) + (255,))
        # snow settled on the lid
        d.rectangle([x + 3, y - 3, x + w - 3, y + 2], fill=SNOW + (255,))
    # a lip of snow in front, so they sit IN the drift rather than on a white line
    d.ellipse([10, base + 4, size - 10, base + 14], fill=SNOW + (255,))
    return im.filter(ImageFilter.SMOOTH)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=LIVE_MEDIA, help="where to write (default: the live Media folder)")
    ap.add_argument("--media", default=LIVE_MEDIA, help="where to read the existing art from")
    args = ap.parse_args()

    src = os.path.join(args.media, "MurlocTacToe_Board.tga")
    if not os.path.exists(src):
        print("can't find %s" % src)
        return 1
    os.makedirs(args.out, exist_ok=True)

    made = [
        ("MurlocTacToe_Board_WinterVeil.tga", freeze_board(src)),
        ("MurlocTacToe_Divider_WinterVeil.tga", build_divider()),
        ("MurlocTacToe_Pile_WinterVeil.tga", build_pile()),
    ]
    for name, img in made:
        path = os.path.join(args.out, name)
        img.save(path)  # uncompressed 32-bit TGA, as the rest of Media is
        print("%-40s %s  %d KB" % (name, img.size, os.path.getsize(path) // 1024))
    print("\nNew files: the game reads textures at startup, so this needs a full restart, not /reload.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
