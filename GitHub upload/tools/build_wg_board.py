"""
Azeroth Almanac - a Wild Gambit board: trim the painting's margin, and undo the window's stretch.

Two things this fixes, which turn out to be one operation.

1. The painted margin. These renders come with a band of plain background outside the ornate frame,
   and sometimes props (candles) sitting in it. Every Board_*.tga is drawn as a fully opaque
   rectangle, so that band becomes a visible border around the board with the window's own wood
   beyond it - it reads as a picture pasted on rather than a board built in. The other boards do
   not show this because their scenes run to the edge of the canvas.

2. The stretch. The window draws a 1024 square texture into 553 x 629, so anything painted is shown
   **13.7% taller than it was painted**. On a board of leaves and stone nobody notices; on one with
   four circular medallions it reads as skewed, because circles become ovals.

Cropping fixes both at once. Cutting only the left and right margins and keeping the full height
makes the picture narrower before it is stretched back to a square, which pre-squashes it
horizontally - exactly the opposite of what the window then does. Crop to the ornament's own edges
(x 30-988 of 1024 here) and the residual stretch falls from 13.7% to 6.4%.

Cropping the top and bottom as well would remove those margins too, but it would push the stretch
up to 16.8% - the crop's aspect is what sets it. Margin beats skew only up to a point: the
horizontal margin is where the hand columns sit, so it is the one that shows.

Usage: python build_wg_board.py <render> <out.png> [x0 x1]
"""
import sys
import numpy as np
from PIL import Image

DRAWN_W, DRAWN_H = 553.0, 629.0          # what ApplyBoard draws a 1024 square into


def ornament_span(a):
    """Where the painted frame starts and stops, ignoring plain background."""
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    mx, mn = a.max(2), a.min(2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    orn = ((G > R + 10) & (G > 60)) | ((R > G * 1.9) & (R > 120)) | ((B > R + 30) & (sat > 0.35))
    cols = orn.sum(0)
    lo = int(np.argmax(cols > 12))
    hi = int(len(cols) - 1 - np.argmax(cols[::-1] > 12))
    return lo, hi


def build(render, x0=None, x1=None):
    im = Image.open(render).convert("RGB")
    if im.size != (1024, 1024):
        im = im.resize((1024, 1024), Image.LANCZOS)
    a = np.asarray(im, np.float32)
    if x0 is None:
        x0, x1 = ornament_span(a)
    cw = x1 - x0
    before = DRAWN_H / DRAWN_W
    after = before * cw / 1024.0
    print("frame spans x %d-%d; cropping to %d wide, full height" % (x0, x1, cw))
    print("stretch seen in game: %.1f%% taller than painted -> %.1f%%"
          % (100 * (before - 1), 100 * (after - 1)))
    return im.crop((x0, 0, x1, 1024)).resize((1024, 1024), Image.LANCZOS), (x0, x1)


if __name__ == "__main__":
    if len(sys.argv) not in (3, 5):
        print(__doc__)
        sys.exit(1)
    bounds = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) == 5 else (None, None)
    img, _ = build(sys.argv[1], *bounds)
    img.save(sys.argv[2])
    print("%s written" % sys.argv[2])
