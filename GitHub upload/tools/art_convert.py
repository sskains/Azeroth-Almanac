"""Convert Gemini art (PNG on flat magenta) to WoW textures (32-bit TGA, powers of two).

  python art_convert.py frame <in.png> <out.tga>          card frame: magenta keyed out, cropped,
                                                         256x512; prints its layout for FRAME_ART
  python art_convert.py full  <in.png> <out.tga> [W H]   whole picture, no keying (default 1024x1024)
  python art_convert.py round <in.png> <out.tga> [size]   round medallion on a flat dark background:
                                                         outside the ring made transparent, squared (default 256)

A frame's layout (fractions of the CARD, the parchment rectangle):
  window = the magenta art window, panel = the dark text panel, band = between them,
  bleed = how far the picture reaches past the card (ornaments over the edge: left, top, right, bottom).
"""
import struct, sys
import numpy as np
from PIL import Image

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

if __name__ == "__main__":
    if sys.argv[1] == "frame":
        frame(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "round":
        round_art(sys.argv[2], sys.argv[3], *(int(v) for v in sys.argv[4:5]))
    else:
        full(sys.argv[2], sys.argv[3], *(int(v) for v in sys.argv[4:6]))


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
