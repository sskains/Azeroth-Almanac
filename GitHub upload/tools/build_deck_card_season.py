"""
Azeroth Almanac - the deck on the Wild Gambit table, wearing a holiday's card back.

The deck you see at rest is PAINTED INTO THE FELT (Media/Background_Pick): it is not a card back
texture and nothing in the UI can retint it. tools/build_deck_card.py already lifts that painted
card onto its own small texture (Media/Deck_Card.tga) so it can light up and rise under the mouse.
This does the same cut, then replaces the card's face with a holiday card back before writing it
out, so the UI can lay a Winter Veil deck exactly over the painted Almanac one and cover it.

Why a warp and not a paste: the painted card leans about 30 degrees and is a little wider at the
top than the bottom. Its four corners are read straight off the cut's own silhouette - for a
rotated rectangle the topmost, rightmost, bottommost and leftmost pixels ARE the corners - and the
card back is warped onto that quad. So the new face lands on the painted card's exact footprint,
which is what lets it hide the old one without a rim showing.

Why the new face is blended in rather than simply laid down: the cut keeps the painted card's
drop shadow (the flood fill only takes away felt and wood, and the shadow is neither), so the cut
is a little larger than the card itself. The card back is warped onto the card's quad only, and
everything outside it - the shadow - keeps the pixels it was painted with. Filling the whole cut
instead put a black band down the shadowed right and bottom edges, where the warp had no picture
left to sample.

Why the shading is carried over: a flat card back pasted on reads as a sticker. The painted card's
own broad light - brighter at the top left, falling away to the shadowed lower edge - is taken as a
heavily blurred luminance map (the blur is what drops the compass rose and keeps only the light)
and multiplied back over the new face.

Why the painting and not Media/CardBack_<season>.tga: the card backs in Media have deliberately
worn, part-transparent edges, because a card held in the hand should not be a crisp rectangle. A
deck lying flat on a table should be. Taking the worn texture and keeping only its colour put a
black rim down two sides of the deck, so this reads docs/art_source/CardBack_<season>.png - the
same painting before the wear is applied - and falls back to the texture only if it is missing.

Usage: python build_deck_card_season.py <Media dir> [season]      (default season: WinterVeil)
"""
import sys, os
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_deck_card import build, write_tga, CARD, OUT

BLUR = 9.0        # big enough to lose the compass rose, small enough to keep the card's lighting
SHADE_LO = 0.55   # how dark the carried-over shading is allowed to push the new face
SHADE_HI = 1.25


def corners(alpha):
    """The painted card's four corners, off its own silhouette."""
    ys, xs = np.nonzero(alpha > 128)
    pts = np.stack([xs, ys], 1).astype(np.float64)
    top = pts[np.argmin(pts[:, 1])]
    bottom = pts[np.argmax(pts[:, 1])]
    left = pts[np.argmin(pts[:, 0])]
    right = pts[np.argmax(pts[:, 0])]
    # the card leans clockwise, so topmost is its top-left and it runs round from there
    return [top, right, bottom, left]


def perspective(src_wh, quad):
    """Coefficients mapping the destination quad back into the source rectangle."""
    w, h = src_wh
    src = [(0, 0), (w, 0), (w, h), (0, h)]
    A, b = [], []
    for (dx, dy), (sx, sy) in zip(quad, src):
        A.append([dx, dy, 1, 0, 0, 0, -sx * dx, -sx * dy])
        A.append([0, 0, 0, dx, dy, 1, -sy * dx, -sy * dy])
        b += [sx, sy]
    return np.linalg.solve(np.array(A, np.float64), np.array(b, np.float64))


def shading(rgb, alpha):
    """The painted card's broad light, as a multiplier around 1."""
    lum = (0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2])
    m = alpha > 128
    if not m.any():
        return np.ones_like(lum)
    # fill the table outside the card with the card's own average, so the blur does not
    # drag the green felt in over the card's edge
    lum = np.where(m, lum, lum[m].mean())
    broad = gaussian_filter(lum.astype(np.float32), BLUR)
    return np.clip(broad / max(broad[m].mean(), 1e-6), SHADE_LO, SHADE_HI)


def main(media, season):
    cut = build(media)                                   # the painted card, table removed
    w, h = CARD[2] - CARD[0], CARD[3] - CARD[1]
    cut = cut.crop((0, 0, w, h))
    a = np.asarray(cut, np.float32)
    rgb, alpha = a[..., :3], a[..., 3]

    painting = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "..", "docs", "art_source", "CardBack_%s.png" % season)
    src = painting if os.path.exists(painting) else os.path.join(media, "CardBack_%s.tga" % season)
    print("face: %s" % os.path.normpath(src))
    face = Image.open(src).convert("RGB")
    quad = corners(alpha)
    coeffs = perspective(face.size, quad)
    warped = face.transform((w, h), Image.PERSPECTIVE, coeffs, resample=Image.BICUBIC)
    # where the card itself landed, as against the shadow around it
    cover = Image.new("L", face.size, 255).transform((w, h), Image.PERSPECTIVE, coeffs,
                                                     resample=Image.BICUBIC)
    c = (np.asarray(cover, np.float32) / 255.0)[..., None]
    new = np.asarray(warped, np.float32) * shading(rgb, alpha)[..., None]
    new = new * c + rgb * (1.0 - c)

    card = np.dstack([np.clip(new, 0, 255), alpha]).astype(np.uint8)
    out = Image.new("RGBA", (OUT, OUT), (0, 0, 0, 0))
    out.alpha_composite(Image.fromarray(card, "RGBA"), (0, 0))

    path = os.path.join(media, "Deck_Card_%s.tga" % season)
    write_tga(out, path)
    print("corners (x, y): " + "  ".join("%.0f,%.0f" % (p[0], p[1]) for p in quad))
    print("%s: %dx%d, %d bytes - laid over the painted deck at the panel's top left + (%d, -%d)"
          % (path, OUT, OUT, os.path.getsize(path), CARD[0], CARD[1]))


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "WinterVeil")
