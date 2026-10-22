"""
Azeroth Almanac - a Wild Gambit board, fitted to the window that draws it.

ApplyBoard draws a 1024 square texture into **553 x 629**, so whatever is painted is shown 13.7%
taller than it was. On a board of leaves and stone nobody notices. On one with four circular
medallions it reads as skewed, and it is the first thing anyone says about it.

That is undone here rather than asked for: the picture is squashed vertically by 553/629 before it
is written, so the window's stretch puts it back. Squashing alone would leave the bare middle panel
too short for the nine cards, so the whole picture is enlarged first by just enough to pay for it -
which costs a little off the left and right edges, and that is the cheap edge to lose, because the
hand columns cover it anyway. What the squash gives back at the top and bottom is transparent, and
costs nothing at all.

Which brings up the other thing. A render with an alpha channel keeps it: the frame's own outline
is then what the window shows, against its own wood, with no border. Every older Board_*.tga is a
fully opaque rectangle, so any plain background painted around the frame became a visible mat - the
complaint that started this. A painting with transparent corners has no mat to show.

The playfield is darkened a little (as art_convert.board does) so the cards and their spikes read
against it, and the frame slightly less.

Usage: python build_wg_board.py <render> <out.tga> [--png <also write the source png>]
"""
import sys, os
import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_convert

DRAWN_W, DRAWN_H = 553.0, 629.0     # what ApplyBoard draws a 1024 square into
CARDS_W, CARDS_H = 336.0, 432.0     # the nine slots, on screen
K_FIELD, K_FRAME = 0.72, 0.92       # the playfield is dimmed more than the frame


def panel(im):
    """The largest bare rectangle: no ornament, no transparency."""
    a = np.asarray(im.convert("RGB"), np.float32)
    al = np.asarray(im)[..., 3]
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    mx, mn = a.max(2), a.min(2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    orn = (((G > R + 10) & (G > 60)) | ((R > G * 1.9) & (R > 120))
           | ((B > R + 30) & (sat > 0.35)) | (al < 200))
    orn = ndimage.binary_closing(ndimage.binary_opening(orn, np.ones((5, 5))), np.ones((13, 13)))
    free = (~orn).astype(np.int32)
    h, w = free.shape
    heights = np.zeros(w, np.int32)
    best = (0, 0, 0, 0, 0)
    for y in range(h):
        heights = np.where(free[y] > 0, heights + 1, 0)
        st = []
        for x in range(w + 1):
            hh = heights[x] if x < w else 0
            start = x
            while st and st[-1][1] >= hh:
                sx, sh = st.pop()
                if sh * (x - sx) > best[0]:
                    best = (sh * (x - sx), sx, y - sh + 1, x - 1, y)
                start = sx
            st.append((start, hh))
    return best[1:]


def build(render):
    src = Image.open(render).convert("RGBA")
    if src.size != (1024, 1024):
        src = src.resize((1024, 1024), Image.LANCZOS)
    x0, y0, x1, y1 = panel(src)
    print("panel as painted: %d x %d" % (x1 - x0, y1 - y0))

    squash = DRAWN_W / DRAWN_H
    need = CARDS_H / (DRAWN_H / 1024.0)                 # panel height the cards need, in texture px
    grow = need / ((y1 - y0) * squash)
    if grow < 1.0:
        grow = 1.0                                       # tall enough already; no need to pay for it
    w2, h2 = int(round(1024 * grow)), int(round(1024 * grow * squash))
    print("de-skew: squash %.3f, enlarge %.3f -> %d x %d (crop %d per side, pad %d top and bottom)"
          % (squash, grow, w2, h2, (w2 - 1024) // 2, max(0, (1024 - h2) // 2)))

    big = src.resize((w2, h2), Image.LANCZOS)
    out = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    out.paste(big, ((1024 - w2) // 2, (1024 - h2) // 2))

    p = panel(out)
    print("panel now       : x %d-%d (%d)  y %d-%d (%d)" % (p[0], p[2], p[2]-p[0], p[1], p[3], p[3]-p[1]))
    return out, p


def darken(im, field):
    a = np.asarray(im, np.float32)
    m = np.zeros(a.shape[:2], np.float32)
    m[field[1]:field[3], field[0]:field[2]] = 1.0
    m = ndimage.gaussian_filter(m, 3)
    k = K_FRAME + (K_FIELD - K_FRAME) * m
    rgb = np.clip(a[..., :3] * k[..., None], 0, 255)
    return Image.fromarray(np.dstack([rgb, a[..., 3]]).astype(np.uint8), "RGBA")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    img, p = build(sys.argv[1])
    if "--png" in sys.argv:
        png = sys.argv[sys.argv.index("--png") + 1]
        img.save(png)
        print("%s written" % png)
    art_convert.write_tga(darken(img, p), sys.argv[2])
    print("%s written; inner should centre on (%.0f, %.0f)" % (sys.argv[2], (p[0]+p[2])/2, (p[1]+p[3])/2))
