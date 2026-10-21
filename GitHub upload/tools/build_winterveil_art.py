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

    for name, cw, ch, used in (("Divider", 512, 128, 94), ("Pile", 256, 256, 126)):
        dst = os.path.join(args.out, "MurlocTacToe_%s_WinterVeil.tga" % name)
        h, w = band(src(name), dst, cw, ch, used)
        print("%-40s %d x %d   fills %d x %d  ->  SEASON_LOOK coord = %.4f, h = %d"
              % (os.path.basename(dst), cw, ch, w, h, h / ch, h))

    print("\nNew textures: the game reads them at startup, so this needs a full restart, not /reload.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
