"""(2026-10-13) Wings & Whispers' round portrait: Media/Ring_Class (the celtic band) in gold, and the
dark window the 3D creature shows through.
  python tools/build_wings_ring.py <Media folder>            the ring, the window, the badge
  python tools/build_wings_ring.py <Media folder> feather    WW_Feather.tga
Writes WW_PortraitBack.tga (the dark disc behind the model), WW_PortraitRing.tga (in front of the
model: an opaque dark band from the window's edge out to the gold ring, so the model's square corners
never show, a soft inner shadow, and the gold band) and WW_Badge.tga (a small gold medallion for the
ride count). The window's radius is WINDOW of the ring's: the model frame is a square of that size.
"""
import os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from art_convert import write_tga

WINDOW = 0.68     # the window's radius, of the ring's (keep in step with QoL/WingsWhispers.lua)
SIZE = 256

def gold(lum):
    # luminance 0..1 -> dark bronze, gold, pale gold highlight
    stops = [(0.0, (40, 22, 6)), (0.35, (120, 78, 24)), (0.65, (214, 166, 72)), (0.85, (246, 214, 130)), (1.0, (255, 244, 200))]
    out = np.zeros(lum.shape + (3,))
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        m = (lum >= a) & (lum <= b)
        t = ((lum - a) / (b - a))[m][:, None]
        out[m] = np.array(ca) * (1 - t) + np.array(cb) * t
    return out

def backing(r):
    # the window's colour by radius (0 centre .. 1 edge): dusky slate, darker outward
    c0, c1 = np.array([46, 56, 72]), np.array([10, 12, 16])
    t = np.clip(r, 0, 1)[..., None] ** 1.3
    return c0 * (1 - t) + c1 * t

def main(media):
    yy, xx = np.mgrid[0:SIZE, 0:SIZE] + 0.5
    rr = np.hypot(xx - SIZE / 2, yy - SIZE / 2) / (SIZE / 2)   # 0 centre, 1 the ring's outer edge
    band_in = 0.78   # where the gold band starts (Ring_Class)
    # back: the disc to under the band, opaque
    back = np.zeros((SIZE, SIZE, 4))
    back[..., :3] = backing(rr / band_in)
    back[..., 3] = np.clip((band_in + 0.02 - rr) * 200, 0, 1) * 255
    write_tga(Image.fromarray(back.astype(np.uint8), "RGBA"), os.path.join(media, "WW_PortraitBack.tga"))
    # front: the band from the window out (same colours as the back, so the edge is invisible), a soft
    # shadow inside the window's rim, then the gold ring on top
    ring = Image.open(os.path.join(media, "Ring_Class.tga")).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    ra = np.asarray(ring).astype(float) / 255
    lum = (0.3 * ra[..., 0] + 0.59 * ra[..., 1] + 0.11 * ra[..., 2])
    lum = np.clip((lum - lum[ra[..., 3] > 0.5].min()) / (np.ptp(lum[ra[..., 3] > 0.5]) + 1e-6), 0, 1)
    front = np.zeros((SIZE, SIZE, 4))
    edge = 3.0 / (SIZE / 2)
    mask = np.clip((rr - WINDOW) / edge + 0.5, 0, 1) * (rr < band_in + 0.05)
    shadow = np.clip((rr - (WINDOW - 0.16)) / 0.16, 0, 1) ** 2 * 0.55 * (rr < WINDOW + 0.01)
    a = np.maximum(mask, shadow)
    col = backing(rr / band_in)
    front[..., :3] = col * (mask[..., None] > 0) + (col * 0.4) * (mask[..., None] <= 0)
    front[..., 3] = a
    g = gold(lum)
    ga = ra[..., 3]
    front[..., :3] = front[..., :3] * (1 - ga[..., None]) + g * ga[..., None]
    front[..., 3] = np.maximum(front[..., 3], ga)
    front[..., 3] *= 255
    write_tga(Image.fromarray(np.clip(front, 0, 255).astype(np.uint8), "RGBA"), os.path.join(media, "WW_PortraitRing.tga"))
    # badge: a small medallion, 64 px: dark centre, the gold band
    small = Image.fromarray(np.clip(front, 0, 255).astype(np.uint8), "RGBA")
    b = np.zeros((SIZE, SIZE, 4))
    b[..., :3] = backing(rr / band_in) * 0.8
    b[..., 3] = (rr < band_in + 0.02) * 255
    bimg = Image.fromarray(b.astype(np.uint8), "RGBA")
    ring_only = np.zeros((SIZE, SIZE, 4))
    ring_only[..., :3] = g
    ring_only[..., 3] = ga * 255
    bimg.alpha_composite(Image.fromarray(ring_only.astype(np.uint8), "RGBA"))
    write_tga(bimg.resize((64, 64), Image.LANCZOS), os.path.join(media, "WW_Badge.tga"))

if __name__ == "__main__" and len(sys.argv) == 2:
    main(sys.argv[1])

def feather(media):
    """(2026-10-13) a small soft feather, near white (tinted in game per creature): WW_Feather.tga, 64 px,
    pointing up, a little curved: a fine shaft, vanes of barbs swept toward the tip (the left one wider),
    wispy edges, a couple of splits and a fluffy, downy base."""
    S = 256
    rng = np.random.default_rng(7)
    yy, xx = np.mgrid[0:S, 0:S] + 0.5
    t = 1 - yy / S                                   # 0 bottom .. 1 tip
    cx = S / 2 + 0.07 * S * np.sin(t * np.pi * 0.85) - 0.02 * S
    dx = xx - cx
    side = np.where(dx < 0, 1.15, 0.85)              # the left vane wider
    prof = np.clip((t - 0.06) / 0.94, 0, 1)
    width = 0.15 * S * side * np.sin(prof ** 0.6 * np.pi) ** 0.8
    ad = np.abs(dx)
    u = ad / np.maximum(width, 1)                    # 0 shaft .. 1 the vane's edge
    # barbs: lines swept up and out from the shaft
    phase = (yy + ad * 1.25) * 0.9
    barb = 0.5 + 0.5 * np.cos(phase)
    wisp = np.clip((1 - u) * 4, 0, 1) + (u > 0.75) * barb * 0.0
    edge = np.clip((1 - u) / 0.35, 0, 1) * (0.55 + 0.45 * barb)   # wispy toward the edge
    body = (u < 1) * np.clip(edge, 0, 1)
    # splits: thin gaps along a barb line
    for at, sgn in ((0.42, -1), (0.66, 1)):
        line = np.abs((yy - (1 - at) * S) + ad * 1.25 * 0.8)
        gap = np.clip(line / 2.5, 0, 1)
        body = body * np.where((np.sign(dx) == sgn) & (u > 0.2), 0.2 + 0.8 * gap, 1)
    # downy base: soft, broken
    down = (t < 0.28)
    noise = rng.random((S, S))
    body = np.where(down, body * (0.35 + 0.5 * noise) * np.clip(t / 0.28, 0.3, 1), body)
    shaft = np.clip(1 - ad / 2.0, 0, 1) * (t < 0.97) * (t > 0.0)
    shade = 0.82 + 0.18 * (1 - u)
    lum = np.clip(shade * (0.88 + 0.12 * barb), 0, 1) * (1 - 0.3 * shaft)
    a = np.clip(np.maximum(body * 0.92, shaft), 0, 1)
    img = np.zeros((S, S, 4))
    img[..., 0] = lum * 255
    img[..., 1] = lum * 251
    img[..., 2] = lum * 242
    img[..., 3] = a * 255
    out = Image.fromarray(img.astype(np.uint8), "RGBA").resize((64, 64), Image.LANCZOS)
    write_tga(out, os.path.join(media, "WW_Feather.tga"))

if __name__ == "__main__" and len(sys.argv) > 2 and sys.argv[2] == "feather":
    feather(sys.argv[1])
