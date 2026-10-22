"""
Azeroth Almanac - the seasonal dress for the Almanac's own windows (placeholder art).

Four small textures, generated rather than painted so the code can be finished and looked at before
the real art exists. Every one is alpha-keyed and meant to sit over the window's own border.

  Season_Snow_Top     1024 x 64    FOUR different drifts of snow side by side, each in its own
                                   quarter. The window lays them along its top edge as separate
                                   patches with gaps; one drift reused for all of them reads as a
                                   copy-and-paste job however much it is scaled and flipped, which
                                   is what four of them are for. Each quarter is faded to nothing
                                   at its own left and right ends and along its top.
  Season_Frost_Corner  128 x 128   frost creeping in from the top-left corner; the other three
                                   corners are this one mirrored, so it must look right flipped.
  Season_Emblem_Sprig   64 x 64    a cap of snow for the top of the round gold emblem.
  Season_Minimap_Cap    64 x 64    the same idea for the minimap button, which is smaller and
                                   rounder, so it is drawn separately rather than scaled.

Painted replacements go in docs/art_source as Season_<name>.png, on flat magenta, and are picked
up automatically: pass --painted. They are keyed, resized to the sizes above, and the snow strip is
made to tile here rather than asked for - blending a strip's own edges together is a few lines, and
no generator has yet been talked into a seamless repeat.

Usage: python build_season_decor.py <Media dir> [--painted <art_source dir>]
"""
import sys, os
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

rng = np.random.default_rng(7)


def noise(shape, scale, octaves=3):
    out = np.zeros(shape, np.float32)
    amp = 1.0
    for o in range(octaves):
        n = gaussian_filter(rng.random(shape).astype(np.float32), scale / (2 ** o))
        n = (n - n.min()) / max(float(n.max() - n.min()), 1e-6)
        out += n * amp
        amp *= 0.5
    return out / out.max()


def rgba(rgb, a):
    h, w = a.shape
    out = np.zeros((h, w, 4), np.float32)
    out[..., :3] = np.array(rgb, np.float32)
    out[..., 3] = np.clip(a, 0, 1) * 255
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def snow_sheet(cols=4, w=256, h=64):
    """Four generated drifts side by side, each a little different, as the painted sheet will be."""
    sheet = Image.new("RGBA", (w * cols, h), (0, 0, 0, 0))
    for c in range(cols):
        sheet.paste(snow_top(w, h, seed=c), (c * w, 0))
    return sheet


def snow_top(w=256, h=64, seed=0):
    """Snow lying along the top, its lower edge uneven, with a few icicles under it."""
    yy, xx = np.mgrid[0:h, 0:w]
    # the drift's depth varies along the strip; wrap-safe, so tiling does not show a seam
    k = 2 * np.pi / w
    s = 1.0 + 0.7 * seed
    depth = (17 + 4 * seed + 7 * np.sin(k * xx * s) + 4 * np.sin(2 * k * xx + 1.1 * s)
             + 3 * np.sin(3 * k * xx + 2.3 * s))
    a = np.clip((depth - yy) / 4.0, 0, 1)
    # icicles: a few narrow spikes hanging from the drift
    spikes = (((38, 26, 2.0), (96, 17, 1.6), (150, 30, 2.2), (206, 20, 1.8)),
              ((60, 20, 1.8), (128, 31, 2.1), (196, 14, 1.5)),
              ((24, 15, 1.6), (84, 28, 2.0), (140, 19, 1.7), (188, 25, 1.9), (232, 12, 1.4)),
              ((70, 33, 2.3), (160, 18, 1.7)))[seed % 4]
    for cx, length, width in spikes:
        d = np.abs(xx - cx)
        tip = depth + length
        spike = (yy > depth - 3) & (yy < tip) & (d < width * (1 - (yy - depth) / max(length, 1)))
        a = np.maximum(a, spike.astype(np.float32))
    a *= 0.55 + 0.45 * noise((h, w), 3)
    a = gaussian_filter(a, 0.7)
    shade = 0.88 + 0.12 * noise((h, w), 4)
    img = np.zeros((h, w, 4), np.float32)
    img[..., 0] = 236 * shade; img[..., 1] = 243 * shade; img[..., 2] = 255 * shade
    img[..., 3] = np.clip(a, 0, 1) * 255
    return Image.fromarray(img.astype(np.uint8), "RGBA")


def frost_corner(s=128):
    """Frost reaching in from the top-left: strongest in the corner, fingers thinning inwards."""
    yy, xx = np.mgrid[0:s, 0:s]
    d = np.hypot(xx, yy) / (s * 0.95)
    fingers = noise((s, s), 5, 4)
    a = np.clip((1.0 - d) * 1.35 - 0.35, 0, 1) * (0.35 + 0.95 * fingers)
    a = np.clip(a * 1.5 - 0.18, 0, 1)
    a = gaussian_filter(a, 1.0) * 0.8
    return rgba((228, 240, 255), a)


def cap(s=128, circle=0.40, bulge=0.085, spread=1.15, drips=((-0.17, 0.055), (0.09, 0.075), (0.26, 0.045))):
    """Snow lying on the top of a round thing.

    The first attempt filled downwards from the top of the texture, which gave a white block with a
    flat top - snow does not do that on a dome. This is the intersection of two shapes instead: a
    disc a little larger than the object, whose edge is lumpy, and everything above a wavy line
    across it. So the upper edge follows the curve it has settled on, with an uneven lip, and the
    lower edge is where the snow stops, with a few drips hanging under it.

    `circle` is the object's radius as a fraction of the texture, so the texture must be drawn
    bigger than the object it caps - at circle*2 of its own width - to leave room for the snow.
    """
    yy, xx = np.mgrid[0:s, 0:s]
    x = (xx - s / 2.0) / s
    y = (yy - s / 2.0) / s
    r = np.hypot(x, y)
    th = np.arctan2(x, -y)                       # 0 straight up, + to the right

    lump = noise((s, s), s * 0.06, 3)
    outer = circle + bulge * np.cos(np.clip(th / spread, -1, 1) * (np.pi / 2)) ** 0.55
    outer = outer * (0.93 + 0.14 * lump)

    # the lower edge: a wavy line, lowest in the middle where snow gathers deepest
    line = -circle * 0.65 + 0.26 * x * x + 0.012 * np.sin(x * 24) + 0.018 * (lump - 0.5)
    a = ((r < outer) & (y < line)).astype(np.float32)

    # a few drips hanging below it
    for dx, length in drips:
        d = np.abs(x - dx)
        tip = line + length
        a = np.maximum(a, (((y > line - 0.01) & (y < tip) & (r < outer)
                            & (d < 0.020 * np.clip(1 - (y - line) / max(length, 1e-6), 0, 1) ** 0.6)).astype(np.float32)))

    a = gaussian_filter(a, s * 0.013)
    a = np.clip((a - 0.28) / 0.5, 0, 1)      # a soft edge, without the staircase a hard cut leaves
    shade = 0.86 + 0.14 * noise((s, s), s * 0.05)
    img = np.zeros((s, s, 4), np.float32)
    img[..., 0] = 238 * shade; img[..., 1] = 245 * shade; img[..., 2] = 255 * shade
    img[..., 3] = a * 255
    return Image.fromarray(img.astype(np.uint8), "RGBA")


def seamless(img, blend=0.18):
    """Make a strip repeat without a seam: cross-fade its left edge over its right."""
    a = np.asarray(img.convert("RGBA"), np.float32)
    h, w = a.shape[:2]
    n = max(1, int(w * blend))
    ramp = np.linspace(0, 1, n, dtype=np.float32)[None, :, None]
    head, tail = a[:, :n].copy(), a[:, -n:].copy()
    a[:, -n:] = tail * (1 - ramp) + head * ramp
    a = a[:, : w - n]                       # the copied head is dropped, so the ends now meet
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def key_background(img, near=40.0, far=100.0):
    """Take out the flat background, whatever shade of magenta it actually is.

    art_convert.key_magenta is tuned for pure #FF00FF and measures how magenta a pixel is. These
    renders come back on a muted pink - around (175, 55, 140) - which that test scores at 0.21, so
    it would leave the background four fifths opaque. The background here is flat and nothing
    painted on it is pink, so it is keyed by distance from the colour the border actually is.

    The edge pixels are a mix of snow and background, so the background is then divided back out of
    them (un-premultiplying); without that every edge keeps a pink fringe that shows against the
    window's own art.
    """
    a = np.asarray(img.convert("RGB"), np.float32)
    h, w = a.shape[:2]
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    bg = np.median(border, axis=0)
    d = np.sqrt(((a - bg) ** 2).sum(2))
    alpha = np.clip((d - near) / (far - near), 0, 1)
    safe = np.maximum(alpha, 1e-3)[..., None]
    rgb = np.clip((a - bg * (1.0 - alpha[..., None])) / safe, 0, 255)
    return Image.fromarray(np.dstack([rgb, alpha * 255]).astype(np.uint8), "RGBA")


def trim(img, pad=0.0):
    """Crop to what is painted, so an inset drawing still reaches the texture's own edges."""
    bbox = img.split()[3].point(lambda v: 255 if v > 10 else 0).getbbox()
    return img.crop(bbox) if bbox else img


def soften_top(img, frac=0.22, blur=1.4):
    """Fade the top of the drift out, so it comes from behind the frame instead of ending on a line.

    The painted drift runs to the very top of its picture. Drawn at 30 px that top is a straight
    horizontal cut of bright white across the window - which is what reads as harsh. Taking the
    alpha smoothly to nothing over the top fifth makes the snow appear to emerge from under the
    window's own border, which is where it would have settled.
    """
    a = np.asarray(img.convert("RGBA"), np.float32)
    h = a.shape[0]
    n = max(2, int(h * frac))
    ramp = np.clip(np.linspace(0.0, 1.0, n), 0, 1) ** 1.6
    a[:n, :, 3] *= ramp[:, None]
    a[..., 3] = gaussian_filter(a[..., 3], blur)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def find_drifts(img, gap=8, least=12):
    """The separate drifts on a painted sheet, found by the bare columns between them.

    Counting panels does not work: asked for four, the painter made the "broken ridge with a gap"
    out of two clumps, which is right, but that makes five runs and its gap is no wider than the
    gaps between the panels - about eleven pixels either way - so no threshold tells them apart.
    They are simply not merged, and sheet_from_drifts keeps the widest four, which drops the
    smaller half of the broken ridge and leaves four drifts that do differ.
    """
    a = np.asarray(img.convert("RGBA"), np.float32)[..., 3]
    on = a.max(0) > 24
    runs, s = [], None
    for i, v in enumerate(on):
        if v and s is None:
            s = i
        if not v and s is not None:
            if i - s > least:
                runs.append([s, i - 1])
            s = None
    if s is not None:
        runs.append([s, len(on) - 1])
    merged = []
    for r in runs:
        if merged and r[0] - merged[-1][1] < gap:
            merged[-1][1] = r[1]
        else:
            merged.append(r)
    return merged, a


def sheet_from_drifts(img, want=4):
    """Lay each painted drift into its own equal cell, ridges aligned along the top.

    The drifts differ wildly in height - one has an icicle three times the depth of its own ridge -
    so cells are sized to the tallest and the rest are padded, not stretched. They keep the scale
    they were painted at relative to each other, which is what makes one read as deep and heavy and
    another as shallow. Prints the cell's shape, which `stripAspect` in WindowUtil must match.
    """
    runs, alpha = find_drifts(img)
    if len(runs) < 2:
        return None
    if len(runs) > want:                       # keep the widest, which are the ones worth seeing
        runs = sorted(sorted(runs, key=lambda r: r[1] - r[0])[-want:], key=lambda r: r[0])
    tops, bots = [], []
    for x0, x1 in runs:
        ys = np.where(alpha[:, x0:x1 + 1].max(1) > 24)[0]
        tops.append(ys.min())
        bots.append(ys.max())
    top = min(tops)
    cw = max(x1 - x0 + 1 for x0, x1 in runs)
    ch = max(bots) - top + 1
    sheet = Image.new("RGBA", (cw * len(runs), ch), (0, 0, 0, 0))
    src = img.convert("RGBA")
    for i, (x0, x1) in enumerate(runs):
        cell = src.crop((x0, top, x1 + 1, top + ch))
        sheet.paste(cell, (i * cw + (cw - (x1 - x0 + 1)) // 2, 0))
    print("  %d drifts, cell %d x %d -> stripCells = %d, stripAspect = %.2f"
          % (len(runs), cw, ch, len(runs), cw / ch))
    return sheet


def make_sheet(img, cols=4, take=0.55):
    """Build a sheet of several drifts out of a painting that holds only one.

    The ideal source is four drifts painted separately. Until there is one, four different stretches
    of a single painted drift are taken - overlapping, so each gets its own lumps and its own
    icicles - and every other one is mirrored. That is real variety, not the same picture scaled:
    the window draws a different cell for each patch, and the eye stops finding the repeat.
    """
    a = img.convert("RGBA")
    w, h = a.size
    cw = int(w * take)
    step = (w - cw) / max(cols - 1, 1)
    sheet = Image.new("RGBA", (cw * cols, h), (0, 0, 0, 0))
    for c in range(cols):
        x = int(c * step)
        cell = a.crop((x, 0, x + cw, h))
        if c % 2 == 1:
            cell = cell.transpose(Image.FLIP_LEFT_RIGHT)
        sheet.paste(cell, (c * cw, 0))
    return sheet


def soften_cells(img, cols=4, frac=0.10):
    """Fade each drift on the sheet away at its own ends, not just the sheet's.

    The sheet holds four drifts side by side and the window draws one at a time, so a fade at the
    sheet's outer edges would leave the two inner drifts cut off where they meet their neighbours.
    """
    a = np.asarray(img.convert("RGBA"), np.float32)
    w = a.shape[1]
    cw = w // cols
    n = max(2, int(cw * frac))
    ramp = np.clip(np.linspace(0.0, 1.0, n), 0, 1) ** 1.3
    for c in range(cols):
        x0 = c * cw
        x1 = x0 + cw
        a[:, x0:x0 + n, 3] *= ramp[None, :]
        a[:, x1 - n:x1, 3] *= ramp[::-1][None, :]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def soften_ends(img, frac=0.10):
    """Fade the drift away at both ends.

    The drift is no longer tiled edge to edge - it is laid along the window as separate patches,
    because an unbroken ribbon of snow reads as a white streak however soft its top is. Each patch
    draws the whole texture, so the texture has to end in thin air at both ends rather than being
    cut off mid-drift.
    """
    a = np.asarray(img.convert("RGBA"), np.float32)
    w = a.shape[1]
    n = max(2, int(w * frac))
    ramp = np.clip(np.linspace(0.0, 1.0, n), 0, 1) ** 1.3
    a[:, :n, 3] *= ramp[None, :]
    a[:, w - n:, 3] *= ramp[::-1][None, :]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def painted(src, size, strip=False, corner=False):
    """A painted texture: background keyed out, resized to what the game draws."""
    img = key_background(Image.open(src))
    if corner:
        img = trim(img)
    if strip:
        img = soften_top(trim(img))
        built = sheet_from_drifts(img)
        img = built if built is not None else make_sheet(img)
        img = soften_cells(img, cols=4)
    return img.resize(size, Image.LANCZOS)


def write_tga(img, path):
    import struct
    img = img.convert("RGBA")
    w, h = img.size
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    with open(path, "wb") as f:
        f.write(hdr + img.transpose(Image.FLIP_TOP_BOTTOM).tobytes("raw", "BGRA"))


WANTED = {"Season_Snow_Top": (1024, 256), "Season_Frost_Corner": (128, 128),
          "Season_Emblem_Sprig": (128, 128), "Season_Minimap_Cap": (64, 64)}


def main(media, art=None):
    for name, img in (("Season_Snow_Top", snow_sheet()),
                      ("Season_Frost_Corner", frost_corner()),
                      ("Season_Emblem_Sprig", cap(128)),
                      ("Season_Minimap_Cap", cap(64, 0.40, 0.10, 1.25, ((-0.15, 0.05), (0.14, 0.06))))):
        src = art and os.path.join(art, name + ".png")
        if src and os.path.exists(src):
            img = painted(src, WANTED[name], strip=(name == "Season_Snow_Top"),
                          corner=(name == "Season_Frost_Corner"))
            print("  (painted: %s)" % os.path.basename(src))
        p = os.path.join(media, name + ".tga")
        write_tga(img, p)
        print("%-22s %-9s %d bytes" % (name, "%dx%d" % img.size, os.path.getsize(p)))


if __name__ == "__main__":
    if len(sys.argv) not in (2, 4) or (len(sys.argv) == 4 and sys.argv[2] != "--painted"):
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[3] if len(sys.argv) == 4 else None)
