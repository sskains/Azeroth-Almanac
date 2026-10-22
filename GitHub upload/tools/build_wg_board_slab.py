"""
Azeroth Almanac - Wild Gambit's Winter Veil board: impose a clean panel on the painting.

Five renders in, the generator would not produce a board this frame can use, and the reason is
arithmetic rather than carelessness. The card grid needs a bare panel of about 624 x 705 of a 1024
square. That leaves a border of roughly 200 px, and the corner medallions kept coming back about
290 px across. A 290 px disc cannot sit in a 200 px band without hanging over the panel, so every
render either kept the medallions and fouled the corner cards, or obeyed and shrank the panel until
ApplyBoard had to magnify the picture and run its frame off the window.

So the panel is imposed here instead of asked for. A rectangle exactly the size the game needs is
laid over the middle; the medallions keep their painted size and tuck behind its edge, which reads
as a stone plate set into the frame. Nothing is scaled, so the painting keeps its own detail.

The panel is NOT new stone. The painting's own middle is kept - its cracks and grain are what makes
it look painted rather than filled - and only the four corners, where the ring, beard, antlers and
horn reach in, are repainted with stone sampled from further into the same slab. Mirroring a tile
to make the panel was tried first and the butterfly symmetry was obvious at a glance.

Usage: python build_wg_board_slab.py <render> <out.png>
"""
import sys
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

# the panel the game needs, with ~10 px to spare round the nine cards
SLAB = (190, 147, 834, 877)
# corner, where to take replacement stone from, and how far in to repaint
CORNERS = [((0, 0), (255, 245), 330),    # top left: the yeti's ring and beard
           ((1, 0), (-250, 260), 330),   # top right: the stag's ring
           ((0, 1), (265, -250), 380),   # bottom left: the antlers, which reach furthest in
           ((1, 1), (-245, -265), 330)]  # bottom right: the yeti's horn
EDGE_DARK, TOP_LIGHT, DROP = 0.40, 0.20, 0.45


def build(render):
    src = Image.open(render).convert("RGB")
    if src.size != (1024, 1024):
        src = src.resize((1024, 1024), Image.LANCZOS)
    sw, sh = SLAB[2] - SLAB[0], SLAB[3] - SLAB[1]
    base = np.asarray(src.crop(SLAB), np.float32)
    out = base.copy()
    yy, xx = np.mgrid[0:sh, 0:sw]
    for (cx, cy), (dx, dy), r in CORNERS:
        ox, oy = (0 if cx == 0 else sw - 1), (0 if cy == 0 else sh - 1)
        m = np.clip((r - np.hypot(xx - ox, yy - oy)) / 90.0, 0, 1)
        m = gaussian_filter(m.astype(np.float32), 18)[..., None]
        out = base[np.clip(yy + dy, 0, sh - 1), np.clip(xx + dx, 0, sw - 1)] * m + out * (1 - m)

    edge = np.minimum.reduce([xx, yy, sw - 1 - xx, sh - 1 - yy]).astype(np.float32)
    out *= (1.0 - EDGE_DARK * np.exp(-edge / 9.0))[..., None]
    out *= (1.0 + TOP_LIGHT * np.exp(-yy / 8.0) - 0.10 * np.exp(-(sh - 1 - yy) / 8.0))[..., None]

    full = np.asarray(src, np.float32)
    m = Image.new("L", src.size, 0)
    ImageDraw.Draw(m).rectangle(SLAB, fill=255)
    full *= (1.0 - DROP * gaussian_filter(np.asarray(m, np.float32) / 255.0, 11))[..., None]
    res = Image.fromarray(np.clip(full, 0, 255).astype(np.uint8))
    res.paste(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)), (SLAB[0], SLAB[1]))
    return res


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    img = build(sys.argv[1])
    img.save(sys.argv[2])
    print("%s: panel %d x %d at %s" % (sys.argv[2], SLAB[2]-SLAB[0], SLAB[3]-SLAB[1], SLAB))
