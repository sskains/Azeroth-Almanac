"""Convert Gemini art (PNG on flat magenta) to WoW textures (32-bit TGA, powers of two).

  python art_convert.py frame <in.png> <out.tga>          card frame: magenta keyed out, cropped,
                                                         256x512; prints its layout for FRAME_ART
  python art_convert.py full  <in.png> <out.tga> [W H]   whole picture, no keying (default 1024x1024)
  python art_convert.py board <in.png> <out.tga> [k_field k_frame x0,y0,x1,y1]
                                                         framed board on magenta: keyed, whole canvas kept,
                                                         playfield and frame darkened (default 0.72 / 0.92)
  python art_convert.py cut   <in.png> <out.tga> <W> <H> [fill] [keep]
                                                         piece on magenta: keyed, cropped, fitted into a
                                                         W x H canvas (top left; or stretched with 'fill');
                                                         prints the used texcoord
  python art_convert.py tray  <in.png> <out.tga> [W H]    landscape tray on magenta -> tall hand tray:
                                                         keyed, quarter turn, end caps kept, middle
                                                         stretched (default 128 x 512)
  python art_convert.py arrow <in.png> <out.tga> [size]   coloured art on a baked grey checkerboard:
                                                         squares keyed out by saturation (default 128)
  python art_convert.py round <in.png> <out.tga> [size]   round medallion on a flat dark background:
                                                         outside the ring made transparent, squared (default 256)
  python art_convert.py roundicon <out folder>            (0.69.2) the slightly rounded icon's mask (64 px) and ring (128 px): Icon_Mask.tga, Icon_Ring.tga
  python art_convert.py ruin <Frame_Dungeon.tga> <out.tga>      (0.69.1) a see-through overlay for the dungeon arch: cracks,
                                                         dirt and soot on the stone, moss, cobwebs in the doorway (scipy)
  python art_convert.py parchment <frame.png> <out.tga> [W H] [shadow=<out.tga>]   (0.69.0, #33) a creature card frame on
                                                         magenta -> only its painted parchment border (the
                                                         card's edge to the iron frame), the inside clear; a
                                                         gap where an ornament sat on it (the top gem) filled
                                                         from beside it (default 256 x 512); 0.69.1: the outer
                                                         edge worn (nibbled, darkened), and with shadow= the
                                                         card's soft drop shadow (8% bigger each way; scipy)

A frame's layout (fractions of the CARD, the parchment rectangle):
  window = the magenta art window, panel = the dark text panel, band = between them,
  bleed = how far the picture reaches past the card (ornaments over the edge: left, top, right, bottom).
"""
import struct, sys
import numpy as np
from PIL import Image, ImageFilter

def write_tga(img, path):
    img = img.convert("RGBA")
    w, h = img.size
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    with open(path, "wb") as f:
        f.write(hdr + img.transpose(Image.FLIP_TOP_BOTTOM).tobytes("raw", "BGRA"))

def key_magenta(a):
    rgb = a[..., :3].astype(float)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mag = np.clip((np.minimum(r, b) - g - 60) / 120.0, 0, 1)
    spill = np.clip(np.minimum(r, b) - g, 0, None) * mag
    rgb[..., 0] -= spill
    rgb[..., 2] -= spill
    return np.dstack([np.clip(rgb, 0, 255), (1 - mag) * 255]).astype(np.uint8), mag

def span(mask_1d, frac):
    idx = np.where(mask_1d >= frac * mask_1d.max())[0]
    return idx.min(), idx.max()

def frame(src, dst):
    a = np.array(Image.open(src).convert("RGB"))
    out, mag = key_magenta(a)
    solid = mag < 0.5
    # everything drawn (card plus any ornament over its edge)
    ys, xs = np.where(solid)
    ax0, ax1, ay0, ay1 = xs.min(), xs.max(), ys.min(), ys.max()
    # the card itself: rows / columns that are mostly solid (ornaments are narrow)
    cy0, cy1 = span(solid.sum(axis=1), 0.6)
    cx0, cx1 = span(solid.sum(axis=0), 0.6)
    W, H = cx1 - cx0 + 1, cy1 - cy0 + 1
    inner = mag[cy0 + 15:cy1 - 15, cx0 + 15:cx1 - 15] > 0.5
    yy, xx = np.where(inner)
    wl, wr, wt, wb = xx.min() + cx0 + 15, xx.max() + cx0 + 15, yy.min() + cy0 + 15, yy.max() + cy0 + 15
    # the text panel: the longest run of dark rows (centre strip) below the window, small gaps
    # bridged; its sides where the middle row of it turns light
    lum = a.mean(axis=2)
    c0, c1 = cx0 + W * 35 // 100, cx0 + W * 65 // 100
    med = np.median(lum[:, c0:c1], axis=1)
    best, run, start, gap = (0, 0), 0, None, 0
    for y in range(wb + 2, cy1):
        if med[y] < 60:
            if start is None:
                start = y
            gap = 0
            if y - start > best[1] - best[0]:
                best = (start, y)
        elif start is not None:
            gap += 1
            if gap > 4:
                start, gap = None, 0
    py0, py1 = best
    mid = (py0 + py1) // 2
    rowl = np.median(lum[mid - 3:mid + 4, :], axis=0)
    xs_dark = [x for x in range(cx0, cx1) if rowl[x] < 60]
    # the run of dark columns through the centre
    px0 = px1 = (cx0 + cx1) // 2
    while px0 > cx0 and rowl[px0 - 1] < 60: px0 -= 1
    while px1 < cx1 and rowl[px1 + 1] < 60: px1 += 1
    fx = lambda x: (x - cx0) / W
    fy = lambda y: (y - cy0) / H
    print("card %dx%d (ratio %.3f)" % (W, H, W / H))
    print("window = { %.4f, %.4f, %.4f, %.4f }," % (fx(wl), fy(wt), fx(wr), fy(wb)))
    print("panel = { %.4f, %.4f, %.4f, %.4f }," % (fx(px0), fy(py0), fx(px1), fy(py1)))
    print("bleed = { %.4f, %.4f, %.4f, %.4f }," % ((cx0 - ax0) / W, (cy0 - ay0) / H, (ax1 - cx1) / W, (ay1 - cy1) / H))
    img = Image.fromarray(out[ay0:ay1 + 1, ax0:ax1 + 1], "RGBA").resize((256, 512), Image.LANCZOS)
    write_tga(img, dst)

def full(src, dst, w=1024, h=1024):
    write_tga(Image.open(src).convert("RGBA").resize((w, h), Image.LANCZOS), dst)

def round_art(src, dst, size=256):
    """A round picture on a flat dark background (a carved ring, a medallion): the ring's bounds
    are measured against the background, everything outside the ellipse goes transparent with a
    soft 1.5 px edge, and it is cropped and squared to size x size."""
    im = Image.open(src).convert("RGB")
    a = np.array(im).astype(float)
    bg = np.median(np.concatenate([a[:12, :12].reshape(-1, 3), a[:12, -12:].reshape(-1, 3),
                                   a[-12:, :12].reshape(-1, 3), a[-12:, -12:].reshape(-1, 3)]), axis=0)
    ys, xs = np.where(np.abs(a - bg).sum(axis=2) > 90)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    cx, cy, rx, ry = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2 + 0.5, (y1 - y0) / 2 + 0.5
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    # distance outside the ellipse edge in pixels (normalised radius scaled by the mean radius)
    dist = (np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2) - 1) * (rx + ry) / 2
    alpha = np.clip(0.5 - dist / 1.5, 0, 1) * 255
    out = np.dstack([a, alpha]).astype(np.uint8)
    img = Image.fromarray(out[y0:y1 + 1, x0:x1 + 1], "RGBA").resize((size, size), Image.LANCZOS)
    print("ring %dx%d at (%d, %d) -> %dx%d" % (x1 - x0 + 1, y1 - y0 + 1, x0, y0, size, size))
    write_tga(img, dst)

def tray(src, dst, w=128, h=512, cap=0.30):
    """A landscape tray painted on flat magenta, made into a tall hand tray that the game stretches
    along its middle only (slice margins: sides 40, ends 72 at the default size): magenta keyed out,
    cropped, a quarter turn, then the two end caps (`cap` of the length each, the coin piles) kept
    in proportion and the middle stretched to fill w x h."""
    a = np.array(Image.open(src).convert("RGB"))
    out, mag = key_magenta(a)
    ys, xs = np.where(mag < 0.5)
    img = Image.fromarray(out[ys.min():ys.max() + 1, xs.min():xs.max() + 1], "RGBA").rotate(90, expand=True)
    sw, sl = img.size  # (width, length) of the turned tray
    c = int(round(sl * cap))
    ch = int(round(c * w / sw))  # an end cap's height at the output width
    parts = [(img.crop((0, 0, sw, c)), ch),
             (img.crop((0, c, sw, sl - c)), h - 2 * ch),
             (img.crop((0, sl - c, sw, sl)), ch)]
    sheet = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    y = 0
    for piece, ph in parts:
        sheet.paste(piece.resize((w, ph), Image.LANCZOS), (0, y))
        y += ph
    write_tga(sheet, dst)
    edge_clean(dst)
    print("tray: end caps %d px, sides 40" % ch)

def arrow(src, dst, size=128):
    """A painted coloured arrow on a baked grey checkerboard (a screenshot of a transparent
    picture): the grey squares (no colour) are keyed out by saturation, the edge colours pulled in
    from the solid parts, cropped square with a small margin."""
    from PIL import ImageFilter
    a = np.array(Image.open(src).convert("RGB")).astype(float)
    mx, mn = a.max(axis=2), a.min(axis=2)
    sat = (mx - mn) / np.maximum(mx, 1)
    alpha = np.clip((sat - 0.10) / 0.35, 0, 1)
    solid = (alpha > 0.95).astype(float)
    # colour for the soft edge: the blurred colour of the solid pixels nearby
    def blur(x, r):
        # (a box blur twice over, by running sums; PIL's blur won't take float images)
        for _ in range(2):
            for axis in (0, 1):
                pad = [(0, 0), (0, 0)]
                pad[axis] = (r + 1, r)
                c = np.cumsum(np.pad(x, pad, mode="edge"), axis=axis)
                x = (np.take(c, range(2 * r + 1, c.shape[axis]), axis=axis)
                     - np.take(c, range(0, c.shape[axis] - 2 * r - 1), axis=axis)) / (2 * r + 1)
        return x
    fill = np.dstack([blur(a[..., c] * solid, 6) / np.maximum(blur(solid, 6), 1e-3) for c in range(3)])
    rgb = np.where((alpha > 0.95)[..., None], a, fill)
    out = np.dstack([rgb, alpha * 255]).clip(0, 255).astype(np.uint8)
    ys, xs = np.where(alpha > 0.5)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    side = int(max(x1 - x0, y1 - y0) * 1.06) + 1
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    crop = Image.fromarray(out[y0:y1 + 1, x0:x1 + 1], "RGBA")
    canvas.paste(crop, ((side - crop.width) // 2, (side - crop.height) // 2))
    write_tga(canvas.resize((size, size), Image.LANCZOS), dst)
    print("arrow %dx%d at (%d, %d) -> %dx%d" % (x1 - x0 + 1, y1 - y0 + 1, x0, y0, size, size))



def board(src, dst, k_field=0.72, k_frame=0.92, field="135,135,890,890", size=1024):
    """A framed game board painted on flat magenta: magenta keyed out, the canvas kept whole (the
    game places it by measured offsets), the playfield (`field` = x0,y0,x1,y1 in source pixels)
    multiplied by k_field and the frame by k_frame, so the board can be darkened without
    re-painting; the playfield's edge is feathered over 6 px."""
    from PIL import ImageFilter
    a = np.array(Image.open(src).convert("RGB"))
    out, mag = key_magenta(a)
    x0, y0, x1, y1 = (int(v) for v in field.split(","))
    mask = np.zeros(out.shape[:2], np.uint8)
    mask[y0:y1, x0:x1] = 255
    mask = np.array(Image.fromarray(mask).filter(ImageFilter.GaussianBlur(3))).astype(float) / 255
    k = k_frame + (k_field - k_frame) * mask
    rgb = out[..., :3].astype(float) * k[..., None]
    out = np.dstack([np.clip(rgb, 0, 255), out[..., 3]]).astype(np.uint8)
    img = Image.fromarray(out, "RGBA")
    if img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    write_tga(img, dst)
    edge_clean(dst)

def cut(src, dst, cw, ch, fill=False, keep=False):
    """A piece painted on flat magenta: keyed out, cropped, scaled to fit a cw x ch canvas
    (power-of-two sizes) in its top-left corner with its shape kept (or, with fill, stretched to
    the whole canvas), the rest transparent. Prints the used fraction, for SetTexCoord.
    All the flat background magenta goes, enclosed loops included. With keep, a pink patch enclosed by the
    art (a highlight inside a gem) is kept; without it the whole picture is keyed plainly."""
    from PIL import ImageDraw
    a = np.array(Image.open(src).convert("RGB"))
    out, mag = key_magenta(a)
    # only the magenta joined to the picture's outside is background: pink-purple highlights
    # inside a gem are art, so they keep their colour and stay solid
    if keep:
        keyed = mag > 0.02  # (any trace of magenta; the outside is what joins up from the corner)
        ky, kx = np.where(mag > 0.5)
        seed = int(np.argmin(ky + kx))  # (the keyed pixel nearest the top left, on the outside)
        outside = np.zeros_like(keyed)
        outside[ky[seed], kx[seed]] = True
        while True:  # (grow the outside through the keyed pixels, four ways, until it stops)
            grown = outside.copy()
            grown[1:, :] |= outside[:-1, :]
            grown[:-1, :] |= outside[1:, :]
            grown[:, 1:] |= outside[:, :-1]
            grown[:, :-1] |= outside[:, 1:]
            grown &= keyed
            if (grown == outside).all():
                break
            outside = grown
        inside = keyed & ~outside
        # Enclosed bits of magenta are told apart: a pocket of the flat background (the loops of a rope, the hole
        # of a ring) goes transparent like the outside, and so do the soft edge pixels round it; a pink patch of
        # the art itself (a highlight inside a gem) is kept. A patch is a pocket when it holds any of the pure
        # background magenta (a few pixels are enough: the smallest rope loops are only a few across).
        from collections import deque
        # (pure = within a hair of this picture's own background colour, read from its corners: the pink in a
        # gem is nearer than "any magenta" but still well away from that exact flat colour)
        corners = np.concatenate([a[:6, :6].reshape(-1, 3), a[:6, -6:].reshape(-1, 3), a[-6:, :6].reshape(-1, 3), a[-6:, -6:].reshape(-1, 3)])
        bgc = np.median(corners, axis=0)
        pure = np.abs(a.astype(int) - bgc.astype(int)).sum(axis=2) < 60
        seen = np.zeros_like(inside)
        keep = np.zeros_like(inside)
        H, W = inside.shape
        for sy, sx in zip(*np.where(inside)):
            if seen[sy, sx]:
                continue
            comp, q = [], deque([(sy, sx)])
            seen[sy, sx] = True
            while q:
                y, x = q.popleft()
                comp.append((y, x))
                for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                    if 0 <= ny < H and 0 <= nx < W and inside[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
            cy, cx = zip(*comp)
            if pure[list(cy), list(cx)].sum() < 4:  # none of the flat background in it: it is art
                keep[list(cy), list(cx)] = True
        out[keep, :3] = a[keep]
        out[keep, 3] = 255
    ys, xs = np.where(mag < 0.5)
    img = Image.fromarray(out[ys.min():ys.max() + 1, xs.min():xs.max() + 1], "RGBA")
    if fill:
        w, h = cw, ch
    else:
        s = min(cw / img.width, ch / img.height)
        w, h = max(1, int(round(img.width * s))), max(1, int(round(img.height * s)))
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    canvas.paste(img.resize((w, h), Image.LANCZOS), (0, 0))
    write_tga(canvas, dst)
    edge_clean(dst)
    print("%s: %dx%d used %dx%d of %dx%d  texcoord 0,%.4f,0,%.4f" % (dst.split("\\")[-1], img.width, img.height, w, h, cw, ch, w / cw, h / ch))

def stage(src, dst, cw=512, ch=256):
    """A stage painted standing in a pool on magenta (a stump in water): like `cut`, then the pool's water,
    which fills a rectangle across the picture, is faded into transparency round the stump (an ellipse,
    and softly along its top edge) so no hard rectangle is left. Prints the used texcoord."""
    cut(src, dst, cw, ch)
    a = np.array(Image.open(dst).convert("RGBA")).astype(float)
    alpha = a[..., 3]
    ys, xs = np.where(alpha > 10)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    u = (xx - x0) / float(x1 - x0)
    v = (yy - y0) / float(y1 - y0)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    water = (b >= g - 5) & (b > r + 10) & ((r + g + b) / 3 < 120) & (alpha > 0)
    d = np.sqrt(((u - 0.5) / 0.56) ** 2 + ((v - 0.68) / 0.36) ** 2)
    fade = np.clip((1.0 - d) / 0.35, 0, 1) * np.clip((v - 0.64) / 0.07, 0, 1)
    a[..., 3] = np.where(water, alpha * fade, alpha)
    write_tga(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA"), dst)
    print("stage: water faded round the stump")

def edge_clean(path, width=2):
    """Pull the magenta fringe off a keyed texture's edges: pixels within `width` of transparency
    that lean magenta (red and blue over green) fade out and lose the tint."""
    from PIL import ImageFilter
    im = Image.open(path).convert("RGBA")
    a = np.array(im).astype(float)
    alpha = a[..., 3]
    holes = alpha < 128
    holes[:width, :] = holes[-width:, :] = True  # (the picture's own edge counts as outside)
    holes[:, :width] = holes[:, -width:] = True
    hole = Image.fromarray((holes * 255).astype(np.uint8))
    near = np.array(hole.filter(ImageFilter.MaxFilter(2 * width + 1))) > 0
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lean = np.clip((np.minimum(r, b) - g - 8) / 50.0, 0, 1) * near
    a[..., 3] = alpha * (1 - lean)
    spill = np.clip(np.minimum(r, b) - g, 0, None) * near
    a[..., 0] -= spill
    a[..., 2] -= spill
    write_tga(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA"), path)

SHADOW_PAD = 0.08

def parchment(src, dst, w=256, h=512, depth=34, dark=135, shadow=None):
    from PIL import ImageFilter
    im = np.asarray(Image.open(src).convert("RGB")).astype(float)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    mag = (r > 200) & (g < 80) & (b > 200)
    ys, xs = np.where(~mag)
    c = im[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    H, W = c.shape[:2]
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    luma = 0.3 * r + 0.59 * g + 0.11 * b
    outer = np.clip((np.sqrt((r - 255) ** 2 + g ** 2 + (b - 255) ** 2) - 60) / 120, 0, 1)
    band = np.zeros((H, W), bool)
    # from each edge inward: parchment until the first dark pixel (the iron frame)
    def walk(coords):
        for k, (y, x) in enumerate(coords):
            if outer[y, x] < 0.5:
                continue
            if luma[y, x] < dark and k > 8:
                break
            band[y, x] = True
    for y in range(H):
        walk([(y, x) for x in range(depth)])
        walk([(y, x) for x in range(W - 1, W - 1 - depth, -1)])
    for x in range(W):
        walk([(y, x) for y in range(depth)])
        walk([(y, x) for y in range(H - 1, H - 1 - depth, -1)])
    m = Image.fromarray((band * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    a = np.asarray(m).astype(float) / 255 * outer
    rgb = c.copy()
    k = 1 - outer
    for ch, mv in ((0, 255), (1, 0), (2, 255)):   # unmix the magenta at the card's edge
        rgb[..., ch] = np.where(outer > 0.05, (c[..., ch] - k * mv) / np.maximum(outer, 0.05), c[..., ch])
    out = np.dstack([np.clip(rgb, 0, 255), a * 255])
    # thin places along an edge (an ornament sat there): copy the nearest full strip, corners left alone
    L = 40
    A = out[..., 3].copy()
    def thick(v):
        d = 0
        for i in range(len(v)):
            if v[i] > 128 or i < 3: d = i
            else: break
        return d
    sides = [
        (W, lambda i: A[:L, i], lambda i: out[:L, i].copy(), lambda i, s: out.__setitem__((slice(0, L), i), s)),
        (W, lambda i: A[H - L:, i][::-1], lambda i: out[H - L:, i].copy(), lambda i, s: out.__setitem__((slice(H - L, H), i), s)),
        (H, lambda i: A[i, :L], lambda i: out[i, :L].copy(), lambda i, s: out.__setitem__((i, slice(0, L)), s)),
        (H, lambda i: A[i, W - L:][::-1], lambda i: out[i, W - L:].copy(), lambda i, s: out.__setitem__((i, slice(W - L, W)), s)),
    ]
    for n, line, get, put in sides:
        ds = np.array([thick(line(i)) for i in range(n)])
        med = np.median(ds[int(n * 0.15):int(n * 0.85)])
        lo, hi = int(n * 0.12), int(n * 0.88)
        good = [i for i in range(lo, hi) if ds[i] >= med - 3]
        strips = {j: get(j) for j in good}
        for i in [i for i in range(lo, hi) if ds[i] < med - 4]:
            cand = [j for j in good if abs(j - i) > 8] or good
            put(i, strips[min(cand, key=lambda j: abs(j - i))])
    # (0.69.1) worn, tattered outer edge: the card's edge nibbled in irregularly (soft noise, a few
    # deeper tears), and darkened toward the edge like old paper, so it isn't a clean rectangle
    from scipy import ndimage
    rng = np.random.default_rng(7)
    solid = out[..., 3] > 128
    filled = ndimage.binary_fill_holes(solid)               # the card's whole shape, inside included
    d = ndimage.distance_transform_edt(filled)               # distance in from the card's outer edge
    n1 = ndimage.gaussian_filter(rng.random((H, W)), 2.0)
    n2 = ndimage.gaussian_filter(rng.random((H, W)), 7.0)
    n1 = (n1 - n1.min()) / (n1.max() - n1.min())
    n2 = (n2 - n2.min()) / (n2.max() - n2.min())
    bite = 1.0 + 5.0 * n1 + 14.0 * np.clip((n2 - 0.66) / 0.34, 0, 1) ** 2    # px eaten from the edge
    keep = np.clip((d - bite) / 1.4, 0, 1)
    out[..., 3] *= keep
    burn = 1 - 0.38 * np.exp(-np.maximum(d - bite, 0) / 3.5)
    out[..., :3] *= burn[..., None]
    # (0.69.1) an abandoned card: water stains and grime blotches, and a few small scorch marks
    stain = np.clip((ndimage.gaussian_filter(rng.random((H, W)), 9.0) - 0.5) * 9, 0, 1)
    out[..., :3] *= (1 - 0.32 * stain)[..., None]
    out[..., :3] += (np.array([-6, -14, -22]) * stain[..., None])         # (browner where stained)
    for _ in range(4):
        cy, cx = rng.uniform(0, H), rng.choice([rng.uniform(0, W * 0.06), rng.uniform(W * 0.94, W)])
        r = rng.uniform(3, 7)
        yy, xx = np.ogrid[:H, :W]
        dist = np.sqrt((yy - cy) ** 2 + (xx - cx) ** 2)
        scorch = np.clip(1 - dist / (r * 2.2), 0, 1) ** 1.6
        out[..., :3] *= (1 - 0.75 * scorch)[..., None]
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    write_tga(img.resize((w, h), Image.LANCZOS), dst)
    print(f"parchment border {W} x {H} -> {w} x {h}: sides {np.median([thick(A[y, :L]) for y in range(H)]) / W:.3f} of the width")
    if shadow:
        # the card's soft drop shadow: its worn shape, filled, blurred, black; drawn PAD of the card's
        # width / height bigger each way (the blur spills past the card)
        shape = ndimage.binary_fill_holes(out[..., 3] > 128).astype(float)
        pw, ph = int(W * SHADOW_PAD), int(H * SHADOW_PAD)
        big = np.zeros((H + 2 * ph, W + 2 * pw))
        big[ph:ph + H, pw:pw + W] = shape
        big = ndimage.gaussian_filter(big, W * 0.022)
        sh = np.zeros(big.shape + (4,))
        sh[..., 3] = np.clip(big * 255, 0, 255)
        write_tga(Image.fromarray(sh.astype(np.uint8), "RGBA").resize((w, h), Image.LANCZOS), shadow)
        print(f"shadow -> {shadow} (pad {SHADOW_PAD} of the card each way)")

def ruin(src, dst, seed=11):
    """(0.69.1) a see-through overlay for the dungeon card's stone arch (Media\\Frame_Dungeon): cracks,
    dirt and soot on the stone only, a little moss, and cobwebs in the doorway's upper corners. Same size
    as the frame; drawn over it."""
    from scipy import ndimage
    from PIL import ImageDraw
    fr = np.asarray(Image.open(src).convert("RGBA")).astype(float)
    H, W = fr.shape[:2]
    S = 2                                                   # (drawn at twice the size, then reduced)
    stone = ndimage.zoom(fr[..., 3] / 255.0, S, order=1) > 0.6
    filled = ndimage.binary_fill_holes(stone)
    window = filled & ~stone                                 # the doorway (the picture shows there)
    HH, WW = stone.shape
    rng = np.random.default_rng(seed)
    out = np.zeros((HH, WW, 4))
    def put(rgb, alpha):
        al = alpha[..., None]
        out[..., :3] = rgb * al + out[..., :3] * (1 - al)
        out[..., 3] = alpha + out[..., 3] * (1 - alpha)
    def noise(sig):
        n = ndimage.gaussian_filter(rng.random((HH, WW)), sig)
        return (n - n.min()) / max(1e-6, n.max() - n.min())
    # dirt and soot in blotches, heavier low down and round the stone's edges
    edge = ndimage.distance_transform_edt(stone)
    dirt = np.clip((noise(14) - 0.45) / 0.35, 0, 1) * 0.55 + np.exp(-edge / 6) * 0.25
    dirt *= np.linspace(0.7, 1.15, HH)[:, None]
    put(np.ones((HH, WW, 3)) * np.array([28, 20, 12]), np.clip(dirt, 0, 0.7) * stone)
    # cracks: a few wandering, branching dark lines
    cr = Image.new("L", (WW, HH), 0)
    d = ImageDraw.Draw(cr)
    ys, xs = np.where(stone)
    for _ in range(14):
        i = rng.integers(len(ys))
        y, x = float(ys[i]), float(xs[i])
        ang = rng.uniform(0, 2 * np.pi)
        for step in range(int(rng.integers(12, 30))):
            ang += rng.normal(0, 0.45)
            ln = rng.uniform(4, 10) * S
            ny, nx = y + np.sin(ang) * ln, x + np.cos(ang) * ln
            d.line((x, y, nx, ny), fill=255, width=int(rng.choice([1, 2, 2, 3])))
            if rng.random() < 0.12:   # a branch
                ba = ang + rng.choice([-1, 1]) * rng.uniform(0.6, 1.2)
                d.line((nx, ny, nx + np.cos(ba) * ln * 2, ny + np.sin(ba) * ln * 2), fill=200, width=1)
            y, x = ny, nx
    crack = np.asarray(cr.filter(ImageFilter.GaussianBlur(0.6))).astype(float) / 255 * stone
    put(np.ones((HH, WW, 3)) * np.array([14, 10, 6]), crack * 0.85)
    # moss: small green clumps along the stone's lower and inner edges
    moss = np.clip((noise(4) - 0.72) / 0.12, 0, 1) * np.exp(-edge / 10) * stone
    moss *= np.linspace(0.5, 1.2, HH)[:, None]
    put(np.ones((HH, WW, 3)) * np.array([70, 92, 38]), np.clip(moss, 0, 0.75))
    # cobwebs in the doorway's two upper corners (where the arch meets the pillars)
    wy, wx = np.where(window)
    if len(wy):
        top, bot = wy.min(), wy.max()
        web = Image.new("L", (WW, HH), 0)
        dw = ImageDraw.Draw(web)
        yrow = int(top + (bot - top) * 0.36)
        cols = np.where(window[yrow])[0]
        for side, cx in (("left", cols.min()), ("right", cols.max())):
            sgn = 1 if side == "left" else -1
            R = (cols.max() - cols.min()) * 0.3
            # strands fanning from the corner into the doorway (from up along the arch to down the pillar),
            # then rings joining them, each sagging a little toward the corner
            ends = []
            for a_ in np.radians(np.linspace(-75, 65, 8)):
                ends.append((cx + np.cos(a_) * R * sgn, yrow + np.sin(a_) * R))
                dw.line((cx, yrow, ends[-1][0], ends[-1][1]), fill=235, width=2)
            for ring in (0.28, 0.5, 0.72, 0.93):
                pts = []
                for k_, (ex, ey) in enumerate(ends):
                    px_, py_ = cx + (ex - cx) * ring, yrow + (ey - yrow) * ring
                    if 0 < k_:
                        qx, qy = pts[-1]
                        mx, my = (qx + px_) / 2, (qy + py_) / 2
                        pts.append((mx + (cx - mx) * 0.12, my + (yrow - my) * 0.12))
                    pts.append((px_, py_))
                dw.line(pts, fill=200, width=1 + (ring > 0.6))
        webm = np.asarray(web.filter(ImageFilter.GaussianBlur(0.5))).astype(float) / 255 * window
        put(np.ones((HH, WW, 3)) * np.array([225, 222, 214]), np.clip(webm * 0.8, 0, 0.75))
    rgb = np.where(out[..., 3:] > 0, out[..., :3], 0)
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), np.clip(out[..., 3] * 255, 0, 255)]).astype(np.uint8), "RGBA")
    write_tga(img.resize((W, H), Image.LANCZOS), dst)
    print(f"ruin overlay {W} x {H} -> {dst}")

def roundicon(folder):
    """Icon_Mask.tga (white rounded square, for a mask texture) and Icon_Ring.tga (its thin edge, white, to be tinted):
    the corner radius is 14% of the side; drawn four times over and scaled down for smooth corners."""
    from PIL import ImageDraw
    def rounded(size, inset, thick=None):
        k = 4
        S = size * k
        r = int(round(size * 0.14 * k))
        img = Image.new("L", (S, S), 0)
        d = ImageDraw.Draw(img)
        d.rounded_rectangle((inset * k, inset * k, S - 1 - inset * k, S - 1 - inset * k), radius=max(r - inset * k // 2, 1), fill=255)
        if thick:
            t = thick * k
            d.rounded_rectangle((inset * k + t, inset * k + t, S - 1 - inset * k - t, S - 1 - inset * k - t), radius=max(r - t, 1), fill=0)
        return img.resize((size, size), Image.LANCZOS)
    def rgba(alpha):
        a = np.array(alpha)
        return Image.fromarray(np.dstack([np.full_like(a, 255)] * 3 + [a]), "RGBA")
    write_tga(rgba(rounded(64, 0)), folder + "\\Icon_Mask.tga")
    write_tga(rgba(rounded(128, 0, 4)), folder + "\\Icon_Ring.tga")
    print("roundicon: Icon_Mask.tga 64 x 64, Icon_Ring.tga 128 x 128 in " + folder)

if __name__ == "__main__":
    if sys.argv[1] == "frame":
        frame(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "board":
        board(sys.argv[2], sys.argv[3], *(float(v) for v in sys.argv[4:6]), *sys.argv[6:7])
    elif sys.argv[1] == "stage":
        stage(sys.argv[2], sys.argv[3], *(int(v) for v in sys.argv[4:6]))
    elif sys.argv[1] == "cut":
        cut(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), "fill" in sys.argv[6:], "keep" in sys.argv[6:])
    elif sys.argv[1] == "tray":
        tray(sys.argv[2], sys.argv[3], *(int(v) for v in sys.argv[4:6]))
    elif sys.argv[1] == "arrow":
        arrow(sys.argv[2], sys.argv[3], *(int(v) for v in sys.argv[4:5]))
    elif sys.argv[1] == "parchment":
        rest = [v for v in sys.argv[4:] if not v.startswith("shadow=")]
        sh = [v[7:] for v in sys.argv[4:] if v.startswith("shadow=")]
        parchment(sys.argv[2], sys.argv[3], *(int(v) for v in rest[:2]), shadow=sh[0] if sh else None)
    elif sys.argv[1] == "roundicon":
        roundicon(sys.argv[2])
    elif sys.argv[1] == "ruin":
        ruin(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "round":
        round_art(sys.argv[2], sys.argv[3], *(int(v) for v in sys.argv[4:5]))
    else:
        full(sys.argv[2], sys.argv[3], *(int(v) for v in sys.argv[4:6]))
