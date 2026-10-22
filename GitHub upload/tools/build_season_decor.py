"""
Azeroth Almanac - the seasonal dress for the Almanac's own windows (placeholder art).

Four small textures, generated rather than painted so the code can be finished and looked at before
the real art exists. Every one is alpha-keyed and meant to sit over the window's own border.

  Season_Snow_Top      256 x 64    a drift of snow with a few icicles. Drawn across the top edge of
                                   every window, TILED horizontally - windows run from about 300 to
                                   900 px wide and one stretched copy would smear - so the left and
                                   right edges of this texture must match.
  Season_Frost_Corner  128 x 128   frost creeping in from the top-left corner; the other three
                                   corners are this one mirrored, so it must look right flipped.
  Season_Emblem_Sprig   64 x 64    a cap of snow for the top of the round gold emblem.
  Season_Minimap_Cap    64 x 64    the same idea for the minimap button, which is smaller and
                                   rounder, so it is drawn separately rather than scaled.

Usage: python build_season_decor.py <Media dir>
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


def snow_top(w=256, h=64):
    """Snow lying along the top, its lower edge uneven, with a few icicles under it."""
    yy, xx = np.mgrid[0:h, 0:w]
    # the drift's depth varies along the strip; wrap-safe, so tiling does not show a seam
    k = 2 * np.pi / w
    depth = 20 + 7 * np.sin(k * xx) + 4 * np.sin(2 * k * xx + 1.1) + 3 * np.sin(3 * k * xx + 2.3)
    a = np.clip((depth - yy) / 4.0, 0, 1)
    # icicles: a few narrow spikes hanging from the drift
    for cx, length, width in ((38, 26, 2.0), (96, 17, 1.6), (150, 30, 2.2), (206, 20, 1.8)):
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


def cap(s=64, width=0.80, depth=0.34):
    """A cap of snow for the top of something round."""
    yy, xx = np.mgrid[0:s, 0:s]
    x = (xx - s / 2) / (s / 2)
    k = 2 * np.pi
    lip = depth * s * (1 - 0.55 * x * x) + 2.5 * np.sin(k * xx / s * 3)
    a = np.clip((lip - yy) / 3.0, 0, 1)
    a[:, : int(s * (1 - width) / 2)] = 0
    a[:, int(s * (1 + width) / 2):] = 0
    a *= 0.6 + 0.4 * noise((s, s), 2)
    a = gaussian_filter(a, 0.8)
    return rgba((238, 245, 255), a)


def write_tga(img, path):
    import struct
    img = img.convert("RGBA")
    w, h = img.size
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    with open(path, "wb") as f:
        f.write(hdr + img.transpose(Image.FLIP_TOP_BOTTOM).tobytes("raw", "BGRA"))


def main(media):
    for name, img in (("Season_Snow_Top", snow_top()),
                      ("Season_Frost_Corner", frost_corner()),
                      ("Season_Emblem_Sprig", cap(64, 0.72, 0.30)),
                      ("Season_Minimap_Cap", cap(64, 0.86, 0.36))):
        p = os.path.join(media, name + ".tga")
        write_tga(img, p)
        print("%-22s %-9s %d bytes" % (name, "%dx%d" % img.size, os.path.getsize(p)))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1])
