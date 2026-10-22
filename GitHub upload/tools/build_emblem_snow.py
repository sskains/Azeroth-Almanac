# -*- coding: utf-8 -*-
"""Snow for the elite gold dragon ring - keyed out of a painting and registered onto the real one.

    python tools/build_emblem_snow.py "<AddOns>/AzerothAlmanac/Media" [--fit]

The ring is Blizzard's own art (the atlas `UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged`),
so it cannot be replaced, only drawn over. What is wanted back from the painter is therefore *snow
alone*, lying where it would lie on that particular dragon - and nothing else, because anything
else would be a second, slightly wrong dragon sitting on the true one.

So two pictures go in:

  Season_Emblem_Ring_clean.png   a screenshot of the real emblem, taken with `/aa season plain`
  Season_Emblem_Ring_snowed.png  the painter's version of it, with snow added

The painter repaints rather than edits, so the snowed one is its own picture at its own size. It
is registered against the screenshot by correlating gradient images - the palette is different but
the shapes are not - which found the two to agree closely enough to lie on top of one another
(see `snow_on_emblem.png` from `--fit`). The snow is then keyed out by colour, which separates
cleanly: nothing else in the picture is white or pale blue, the ornament being gold, the cards
purple and teal and the background dark green.

The result is cut to the ornament's own box, measured off the screenshot, and stretched into a
square texture. The game draws it with `SetAllPoints(e.ring)`, so the stretch is undone there and
the snow lands back on the dragon.

`--fit` searches for the registration again and writes the working pictures beside the output; the
numbers below are what it found, kept so an ordinary build takes a second rather than a minute.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(os.path.dirname(HERE), "docs", "art_source")

CLEAN = "Season_Emblem_Ring_clean.png"
SNOWED = "Season_Emblem_Ring_snowed.png"
OUT = "Season_Emblem_Snow"
SIZE = (256, 256)

# the painting's flat magenta frame, so only the picture itself is read
FRAME = (38, 38, 988, 482)
# painting -> screenshot: x' = TX + x*SX, y' = TY + y*SY
SX, SY, TX, TY = 0.2225, 0.2325, -31, 24
# the painted ornament's box in the screenshot. Blizzard's atlases are packed tight, so this is
# also the box the ring is drawn in - which is why the texture can simply be given the ring's
# corners. The check that it is right: the icon inside is drawn at 74 where the ring is drawn at
# 118, and 74/118 of this box's height, centred, lands on the card art's own edge to within a pixel.
RING = (21, 25, 147, 134)
# the painting stands the ring on a bank of snow across the whole picture. That is ground, not
# ornament, so everything below this line in the painting is dropped.
GROUND = 364.0


def key_snow(img):
    """Snow alone: bright, unsaturated, and never warmer than neutral."""
    a = np.asarray(img.convert("RGB")).astype(float) / 255.0
    v = a.max(2)
    s = np.where(v > 0, (v - a.min(2)) / np.maximum(v, 1e-6), 0)
    warm = a[:, :, 0] - a[:, :, 2]
    alpha = (np.clip((v - 0.42) / 0.30, 0, 1)
             * np.clip((0.34 - s) / 0.22, 0, 1)
             * np.clip((0.06 - warm) / 0.10, 0, 1))
    return Image.fromarray((np.dstack([a, alpha]) * 255).astype(np.uint8), "RGBA")


def drop_ground(img, cut=GROUND, feather=12.0):
    a = np.asarray(img).astype(float) / 255.0
    y = np.arange(a.shape[0])[:, None]
    a[:, :, 3] *= np.clip((cut - y) / feather + 1.0, 0, 1)
    return Image.fromarray((a * 255).astype(np.uint8), "RGBA")


def tidy(img, least=45, mound=(415, 335)):
    """Specks in the card art, and the bank's own mound left beside the claws."""
    from scipy import ndimage
    a = np.asarray(img).astype(float) / 255.0
    m = a[:, :, 3] > 0.3
    lab, n = ndimage.label(m, np.ones((3, 3)))
    for i, sl in enumerate(ndimage.find_objects(lab)):
        size = int((lab == i + 1).sum())
        if size < least or (sl[1].stop < mound[0] and sl[0].start > mound[1]):
            a[:, :, 3][lab == i + 1] = 0
    return Image.fromarray((a * 255).astype(np.uint8), "RGBA")


def place(img, shape):
    """The painting's snow, put where it belongs on the screenshot."""
    w, h = shape
    small = img.resize((int(round(img.width * SX)), int(round(img.height * SY))), Image.LANCZOS)
    pad = 80
    tmp = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    tmp.alpha_composite(small, (TX + pad, TY + pad))
    return tmp.crop((pad, pad, pad + w, pad + h))


def feather_box(img, box=RING, edge=4.0):
    """Nothing is allowed to end in a straight cut at the box's edge - an icicle sliced flat
    reads as a mistake. The top is left alone: snow really does begin at the ring's top edge."""
    a = np.asarray(img).astype(float) / 255.0
    x = np.arange(a.shape[1])[None, :]
    y = np.arange(a.shape[0])[:, None]
    a[:, :, 3] *= (np.clip((x - box[0]) / edge, 0, 1) * np.clip((box[2] - 1 - x) / edge, 0, 1)
                   * np.clip((y - box[1]) / edge + 1, 0, 1) * np.clip((box[3] - 1 - y) / edge, 0, 1))
    return Image.fromarray((a * 255).astype(np.uint8), "RGBA")


def grad(a):
    gy, gx = np.gradient(a)
    return np.hypot(gx, gy)


def _sweep(c, snowed, xs, ys, step):
    h, w = c.shape
    best = None
    for sx in xs:
        for sy in ys:
            nw, nh = int(round(snowed.width * sx)), int(round(snowed.height * sy))
            if nw < 40 or nh < 40 or nw > w + 80 or nh > h + 80:
                continue
            r = grad(np.asarray(snowed.convert("L").resize((nw, nh), Image.LANCZOS)).astype(float) / 255.0)
            r = (r - r.mean()) / (r.std() + 1e-9)
            for tx in range(-50, w - nw + 50, step):
                for ty in range(-50, h - nh + 50, step):
                    x0, y0 = max(0, tx), max(0, ty)
                    x1, y1 = min(w, tx + nw), min(h, ty + nh)
                    if x1 - x0 < nw * 0.8 or y1 - y0 < nh * 0.8:
                        continue
                    sub = c[y0:y1, x0:x1]
                    sub = (sub - sub.mean()) / (sub.std() + 1e-9)
                    score = float((sub * r[y0 - ty:y1 - ty, x0 - tx:x1 - tx]).mean())
                    if best is None or score > best[0]:
                        best = (score, sx, sy, tx, ty)
    return best


def fit(clean, snowed):
    """Find the painting's scale and offset again, by correlating gradient pictures: the palette
    is a repaint but the shapes are not, so the edges still agree. Coarse, then fine around it."""
    c = grad(np.asarray(clean.convert("L")).astype(float) / 255.0)
    coarse = _sweep(c, snowed, np.arange(0.17, 0.251, 0.005), np.arange(0.17, 0.261, 0.005), 2)
    _, sx, sy, _, _ = coarse
    return _sweep(c, snowed, np.arange(sx - 0.005, sx + 0.0051, 0.0025),
                  np.arange(sy - 0.005, sy + 0.0051, 0.0025), 1)


def write_tga(img, path):
    import struct
    img = img.convert("RGBA")
    w, h = img.size
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    with open(path, "wb") as f:
        f.write(hdr + img.transpose(Image.FLIP_TOP_BOTTOM).tobytes("raw", "BGRA"))


def main(media, refit=False):
    clean = Image.open(os.path.join(ART, CLEAN)).convert("RGBA")
    snowed = Image.open(os.path.join(ART, SNOWED)).convert("RGB").crop(FRAME)

    if refit:
        got = fit(clean, snowed)
        print("  fitted: score %.4f  SX %.4f SY %.4f TX %d TY %d" % got)
        print("  (kept constants: SX %.4f SY %.4f TX %d TY %d)" % (SX, SY, TX, TY))

    snow = feather_box(place(tidy(drop_ground(key_snow(snowed))), clean.size))
    snow.save(os.path.join(ART, OUT + ".png"))

    cut = snow.crop(RING).resize(SIZE, Image.LANCZOS)
    path = os.path.join(media, OUT + ".tga")
    write_tga(cut, path)
    print("%-22s %-9s %d bytes" % (OUT, "%dx%d" % cut.size, os.path.getsize(path)))

    if refit:
        look = clean.copy()
        look.alpha_composite(snow)
        look.resize((clean.width * 5, clean.height * 5), Image.LANCZOS) \
            .save(os.path.join(ART, "Season_Emblem_Snow_check.png"))
        print("  wrote Season_Emblem_Snow_check.png - the snow on the real emblem")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--fit"]
    if len(args) != 1:
        print(__doc__)
        sys.exit(1)
    main(args[0], refit="--fit" in sys.argv)
