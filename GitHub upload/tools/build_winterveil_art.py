# -*- coding: utf-8 -*-
"""Murloc Tac Toe's Feast of Winter Veil dress: the Gemini renders into the three textures.

    MurlocTacToe_Board_WinterVeil.tga    1024 x 1024   the frozen pond board
    MurlocTacToe_Divider_WinterVeil.tga   512 x 128     the garland, 94 of the rows used
    MurlocTacToe_Pile_WinterVeil.tga      256 x 256     the presents, 126 of the rows used

    python tools/build_winterveil_art.py            # into the live Media folder
    python tools/build_winterveil_art.py --out DIR  # somewhere else, to look at first

Sources are `docs/art_source/MurlocTacToe_*_WinterVeil.png`, painted on flat magenta (the prompts
are in docs/ART_ASSETS.md). Run it from the repo root; needs Pillow and numpy.

Why this and not `art_convert.py` for all three:

- The **board** does go through `art_convert.board`, with the playfield measured off this render
  (170,170,852,852 rather than the default), so the nine ice panes are darkened and the frame is
  not - that is what keeps a creature readable against them.
- The **divider** can't. `art_convert.banner` writes an opaque RGB picture (it is for zone art) and
  this has to keep its transparency, while `art_convert.cut` scales a piece to fill the canvas and
  pins it top-left. The garland's render is 3.84:1, and filling a 512x128 canvas would leave it
  51 px tall in game - where the three rules it sits between are only 100 px apart and the
  Hallow's End divider is 38. So it is fitted into the same 94-row band as Hallow's End and
  centred, which keeps the side panel's proven spacing and lets the garland's ends taper off as
  they should.
- The **pile** is fitted and centred the same way, inside its 126 rows.

Both bands print the `coord` and `h` that `SEASON_LOOK` in `QoL/MurlocTacToe.lua` wants, so the
numbers in the code can be checked against the art rather than taken on trust.

(Until 2026-10-21 this file derived placeholder art from the mossy board instead, so the dress
could be tested before the paintings existed. The paintings exist.)
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_convert  # noqa: E402  (same folder: key_magenta / write_tga / edge_clean / board)

LIVE_MEDIA = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothAlmanac\Media"
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(HERE, "docs", "art_source")

# the nine ice panes on this render, for art_convert.board's field darkening
BOARD_FIELD = "170,170,852,852"

# Gem Match's eight-by-eight socket grid. Gemini painted it at 128-895 on both axes; the code draws
# the gems at 139-895 across and 129-885 down (its 542 px frame, insets 73.5 / 68.5, eight 50 px
# cells). Eleven pixels is a fifth of a cell once it is drawn, enough to see a gem sitting off its
# socket, so the painting is scaled and shifted onto the code's grid rather than the code moved.
# Measured off the render by counting the sockets themselves - averaging a few columns of pixels
# down the middle of a painted column, and across a painted row - rather than by looking for the
# ribs between them. The ribs are not reliable here: the cracks painted into the ice break a rib
# scan into a dozen false columns, and the frame's inner shadow reads as one more. Counting the
# dark squares gave a clean 8 x 8 both ways.
# (2026-10-22) The third painting's grid, measured: 8 x 8 sockets spanning this. It is within 2% of
# GEM_WANTED, so the picture is drawn essentially one to one - no enlargement, nothing cropped, none
# of the softness the first one picked up. The lantern covered three sockets in the corner and was
# patched out in docs/art_source (the raw render is kept beside it as ..._v2-raw.webp).
# Measured the same way the result is checked - a blueness threshold at 0.6 of the picture's own
# maximum, because the sockets are bevelled and an absolute threshold slides several pixels along
# the slope. Measuring the painting one way and the output another put the grid 8 px out and looked
# like a bug in the alignment, which it was not.
GEM_PAINTED = (129.0, 139.0, 889.0, 895.0)
GEM_WANTED = (139, 129, 895, 885)


def align(im, painted, wanted, fill=(255, 0, 255)):
    """Scale and shift a render so a box in it lands exactly on a box the code expects."""
    sx = (wanted[2] - wanted[0]) / (painted[2] - painted[0])
    sy = (wanted[3] - wanted[1]) / (painted[3] - painted[1])
    ox, oy = wanted[0] - painted[0] * sx, wanted[1] - painted[1] * sy
    print("%-40s align x%.4f/%.4f, offset %+.1f/%+.1f px" % ("", sx, sy, ox, oy))
    return im.transform(im.size, Image.AFFINE, (1 / sx, 0, -ox / sx, 0, 1 / sy, -oy / sy),
                        resample=Image.BICUBIC, fillcolor=fill)


def keyed(path):
    """The render with its magenta taken out, cropped to the paint, as RGBA."""
    a = np.array(Image.open(path).convert("RGB"))
    out, _ = art_convert.key_magenta(a)
    ys, xs = np.where(out[..., 3] > 8)
    return Image.fromarray(out[ys.min():ys.max() + 1, xs.min():xs.max() + 1], "RGBA")


def band(src, dst, cw, ch, used):
    """Fit a piece inside `used` rows at the top of a cw x ch canvas, centred across it.

    The rest of the canvas stays transparent. Returns the size it actually fills, which is what
    the texture's SetTexCoord and its drawn height are worked out from.
    """
    im = keyed(src)
    k = min(cw / im.width, used / im.height)
    w, h = max(1, int(round(im.width * k))), max(1, int(round(im.height * k)))
    im = im.resize((w, h), Image.LANCZOS)
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    canvas.paste(im, ((cw - w) // 2, 0), im)
    art_convert.write_tga(canvas, dst)
    art_convert.edge_clean(dst)
    return h, w


def cardback(src, dst, cw=256, ch=512):
    """A card back: cut from its dark surround, stretched to the sheet, and its edge worn.

    The sheet is 256 x 512 and the game draws it at 92 x 124 with no texture coordinates, so the
    stretch here is what makes it look right in play - Gemini paints an ordinary 3 x 4 card and
    this squashes nothing, it just fills the taller sheet.

    The wear is the point of the rest. CardBack_Almanac and CardBack_Wild are not clean rectangles:
    their cream borders are nibbled and torn, and barely opaque at the outermost row (alpha peaks
    of 23 and 72 there). A crisp new card stands out badly beside them, so the same treatment
    `art_convert.parchment` gives the dungeon card is given here: the edge eaten in irregularly by
    soft noise with a few deeper tears, and darkened as it goes, like a card long in a pocket.
    """
    from scipy import ndimage

    a = np.array(Image.open(src).convert("RGB"), dtype=np.float32)
    h, w, _ = a.shape
    lum = a.mean(-1)

    # the only thing outside the card is its four rounded corners: grow in from each of them
    outside = np.zeros((h, w), bool)
    dark = lum < 32
    for cy, cx in ((0, 0), (0, w - 1), (h - 1, 0), (h - 1, w - 1)):
        if dark[cy, cx]:
            outside[cy, cx] = True
    while True:
        grown = outside.copy()
        grown[1:, :] |= outside[:-1, :]
        grown[:-1, :] |= outside[1:, :]
        grown[:, 1:] |= outside[:, :-1]
        grown[:, :-1] |= outside[:, 1:]
        grown &= dark
        if (grown == outside).all():
            break
        outside = grown

    rgba = np.dstack([a, np.where(outside, 0.0, 255.0)])
    ys, xs = np.where(~outside)
    card = Image.fromarray(rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1].astype(np.uint8), "RGBA")
    # A margin of clear pixels round the card, for two reasons: the wear below measures how far
    # each pixel is from the nearest clear one, so a card touching the canvas edge has nothing to
    # be eaten from (the first go came out untouched, alpha 255 along the top row); and the backs
    # it sits beside leave one themselves - CardBack_Almanac is 98.2% opaque, about two pixels.
    pad = 1
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    canvas.paste(card.resize((cw - 2 * pad, ch - 2 * pad), Image.LANCZOS), (pad, pad))
    out = np.asarray(canvas, dtype=np.float32)

    rng = np.random.default_rng(7)
    solid = out[..., 3] > 128
    filled = ndimage.binary_fill_holes(solid)
    d = ndimage.distance_transform_edt(filled)
    n1 = ndimage.gaussian_filter(rng.random((ch, cw)), 2.0)
    n2 = ndimage.gaussian_filter(rng.random((ch, cw)), 7.0)
    n1 = (n1 - n1.min()) / (n1.max() - n1.min())
    n2 = (n2 - n2.min()) / (n2.max() - n2.min())
    # (lighter than the dungeon card's: that one is meant to look abandoned, this one just old.
    # Tuned to leave about as much of the sheet opaque as CardBack_Almanac does, 98%.)
    bite = 0.6 + 1.8 * n1 + 5.0 * np.clip((n2 - 0.70) / 0.30, 0, 1) ** 2
    keep = np.clip((d - bite) / 1.4, 0, 1)
    out[..., 3] *= keep
    out[..., :3] *= (1 - 0.38 * np.exp(-np.maximum(d - bite, 0) / 3.5))[..., None]

    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    art_convert.write_tga(img, dst)
    return int(np.asarray(img)[0, :, 3].max()), 100.0 * (np.asarray(img)[..., 3] > 200).mean()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=LIVE_MEDIA, help="where to write (default: the live Media folder)")
    ap.add_argument("--source", default=SOURCE, help="where the Gemini renders are")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    def src(name):
        p = os.path.join(args.source, "MurlocTacToe_%s_WinterVeil.png" % name)
        if not os.path.exists(p):
            print("missing source: %s" % p)
            sys.exit(1)
        return p

    board_dst = os.path.join(args.out, "MurlocTacToe_Board_WinterVeil.tga")
    art_convert.board(src("Board"), board_dst, field=BOARD_FIELD)
    print("%-40s 1024 x 1024   (playfield %s)" % ("MurlocTacToe_Board_WinterVeil.tga", BOARD_FIELD))

    # Gem Match: lined up first, then the same field darkening, so the sockets sit back and the
    # frame stays bright. (The lantern Gemini hung over the last column stays: the gems are drawn
    # on top of the board, so it shows between them rather than blocking anything - Shannon's call.)
    gm_src = os.path.join(args.source, "GemMatch_Board_WinterVeil.png")
    if os.path.exists(gm_src):
        lined = align(Image.open(gm_src).convert("RGB"), GEM_PAINTED, GEM_WANTED)
        tmp = os.path.join(args.out, "_gm_aligned.png")
        lined.save(tmp)
        gm_dst = os.path.join(args.out, "GemMatch_Board_WinterVeil.tga")
        art_convert.board(tmp, gm_dst, field="%d,%d,%d,%d" % GEM_WANTED)
        os.remove(tmp)
        print("%-40s 1024 x 1024   (sockets %s)" % ("GemMatch_Board_WinterVeil.tga", "%d,%d,%d,%d" % GEM_WANTED))

    cb_src = os.path.join(args.source, "CardBack_WinterVeil.png")
    if os.path.exists(cb_src):
        edge, opaque = cardback(cb_src, os.path.join(args.out, "CardBack_WinterVeil.tga"))
        print("%-40s 256 x 512   edge alpha %d, opaque %.1f%%  (Almanac: 23 / 98.2%%)"
              % ("CardBack_WinterVeil.tga", edge, opaque))

    for name, cw, ch, used in (("Divider", 512, 128, 94), ("Pile", 256, 256, 126)):
        dst = os.path.join(args.out, "MurlocTacToe_%s_WinterVeil.tga" % name)
        h, w = band(src(name), dst, cw, ch, used)
        print("%-40s %d x %d   fills %d x %d  ->  SEASON_LOOK coord = %.4f, h = %d"
              % (os.path.basename(dst), cw, ch, w, h, h / ch, h))

    print("\nNew textures: the game reads them at startup, so this needs a full restart, not /reload.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
