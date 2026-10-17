"""
Azeroth Almanac - build the CurseForge project icon (CurseForge/icon.png, 400x400).

    python tools/build_icon.py

This is the listing's icon only. The addon's own icon in game is Media\\Logo_Almanac and is not
touched by this.

The picture is made from the addon's own art: the book (Logo_Almanac), the Wild Gambit cards
(Icon_WildGambit) and the tooled leather (Window_Leather), with the title set in the same gold the
dungeon plaques use - tools/wordart.py is imported and called rather than the lettering being
invented a second time.

Four things were added on top of the plain arrangement, each for a reason, and all are tunable
below:

  cold ground   the leather pushed towards slate, with a tight warm pool behind the subject. The
                arrangement is warm art (red and gold) and was sitting on warm ground, so at
                thumbnail size it read as one brown blob. Note the pool is tight: a wide one covers
                the whole tile and the cold corners never show, which defeats the point.
  backlight     a halo built from the subject's own silhouette, so its edges leave the ground. This
                is the single thing that does most for legibility when the icon is small.
  raking light  the book relit at an angle instead of the flat frontal light it was painted with:
                a gradient for form, a sheen band gated on the art's own brightness so it catches
                the gilding rather than smearing the leather, and a bloom on the gold so the emblem
                flares like metal. Pushed harder than MEDIUM it swallows the compass rose.
  sparks, edge  gold motes near the cards, and a thin gold line inside the rim which holds the
                square together once CurseForge rounds the corners.

The title is bent around a circle (a true polar warp, so the letters turn to follow the curve and
stay upright) and the font is LifeCraft, from tools/fonts. The plaques themselves use Marcellus,
which is not shipped with this project; if it is to hand, point FONT at it and re-run.

Known limit: Logo_Almanac is 128x128 and is drawn here at 250, so it is upscaled and sharpened. The
relighting is doing some of the work that real detail would. It holds at 400 and at 96; below that
the lighting and the sparks stop registering and the icon is carried by the book and the cards.
"""
import importlib.util
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MEDIA = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothAlmanac\Media"
FONT = os.path.join(HERE, "fonts", "LifeCraft_Font.ttf")
OUT = os.path.join(ROOT, "CurseForge", "icon.png")

S = 400                     # CurseForge's project icon
COLD = True                 # slate ground; False for the warm leather
POOL = 0.33                 # how wide the warm pool behind the subject is, as a fraction of S
LIGHT = dict(angle=35, form=0.60, sheen=0.80, catch=0.95)   # "medium": Shannon's pick
TITLE_SPAN = 0.40           # how much of a circle the title wraps, in radians
TITLE_WIDTH = 352


def _wordart():
    spec = importlib.util.spec_from_file_location("wordart", os.path.join(HERE, "wordart.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.lines_of = lambda name: [name]      # one line: a banner, not a two-line plaque
    return mod


def art(name):
    return Image.open(os.path.join(MEDIA, name + ".tga")).convert("RGBA")


def fit(im, w):
    h = int(im.size[1] * w / im.size[0])
    out = im.resize((w, h), Image.LANCZOS)
    if w > im.size[0]:
        out = out.filter(ImageFilter.UnsharpMask(radius=2, percent=70, threshold=2))
    return out


def radial(size, inner, outer, colour, power=1.6):
    g = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(g)
    steps = 48
    for i in range(steps, 0, -1):
        r = inner + (outer - inner) * i / steps
        d.ellipse((size / 2 - r, size / 2 - r, size / 2 + r, size / 2 + r),
                  fill=int(255 * ((1 - i / steps) ** power)))
    layer = Image.new("RGBA", (size, size), colour + (0,))
    layer.putalpha(g.filter(ImageFilter.GaussianBlur(size / 28)))
    return layer


def ground():
    bg = art("Window_Leather").crop((60, 60, 964, 964)).resize((S, S), Image.LANCZOS)
    bg = ImageEnhance.Brightness(bg).enhance(0.5 if COLD else 0.55)
    if COLD:
        a = np.asarray(bg, float)
        lum = a[..., :3].mean(axis=2, keepdims=True)
        a[..., :3] = lum * np.array([0.42, 0.58, 0.95]) * 0.85 + a[..., :3] * 0.15
        bg = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    else:
        bg = ImageEnhance.Color(bg).enhance(1.15)
    base = Image.new("RGBA", (S, S), (10, 10, 16, 255) if COLD else (18, 12, 8, 255))
    base.alpha_composite(bg)
    base.alpha_composite(radial(S, 6, S * (POOL if COLD else 0.62), (255, 176, 74)))
    return base


def relight(img, angle=35.0, form=0.55, sheen=0.75, catch=0.9, band=0.30):
    src = np.asarray(img.convert("RGBA"), float)
    h, w = src.shape[:2]
    rgb, a = src[..., :3], src[..., 3:] / 255.0
    ys, xs = np.mgrid[0:h, 0:w].astype(float)
    th = np.radians(angle)
    t = xs * np.cos(th) + ys * np.sin(th)
    t = (t - t.min()) / max(1e-6, (t.max() - t.min()))
    out = rgb * (1.0 + form * (0.5 - t)[..., None])
    lum = rgb.mean(axis=2, keepdims=True) / 255.0
    falloff = np.exp(-((t - 0.34) ** 2) / (2 * band ** 2))[..., None]
    out = out + np.array([255, 243, 214]) * falloff * np.clip((lum - 0.32) / 0.68, 0, 1) ** 1.4 * sheen
    gold = ((rgb[..., 0] > 150) & (rgb[..., 1] > 105) & (rgb[..., 2] < 150)
            & ((rgb[..., 0] - rgb[..., 2]) > 45))
    g = Image.fromarray((gold * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(w / 36))
    out = out + np.array([255, 231, 170]) * (np.asarray(g, float) / 255.0)[..., None] * falloff * catch
    return Image.fromarray(np.dstack([np.clip(out, 0, 255) * (a > 0), a * 255]).astype(np.uint8), "RGBA")


def _sample(src, sx, sy):
    h, w = src.shape[:2]
    x0, y0 = np.floor(sx).astype(int), np.floor(sy).astype(int)
    fx, fy = (sx - x0)[..., None], (sy - y0)[..., None]
    out = np.zeros(sx.shape + (4,), float)
    for dy in (0, 1):
        for dx in (0, 1):
            xi, yi = x0 + dx, y0 + dy
            ok = (xi >= 0) & (xi < w) & (yi >= 0) & (yi < h)
            vals = np.zeros(sx.shape + (4,), float)
            vals[ok] = src[np.clip(yi, 0, h - 1)[ok], np.clip(xi, 0, w - 1)[ok]]
            out += vals * ((fx if dx else 1 - fx) * (fy if dy else 1 - fy)) * ok[..., None]
    return out


def arc(img, span=0.40, pad=12):
    """Bend a strip around a circle, dome upwards. A polar warp, not a shear."""
    src = np.asarray(img.convert("RGBA"), float)
    h, w = src.shape[:2]
    R = w / span
    inner, outer = R - h / 2.0, R + h / 2.0
    half = span / 2.0
    W = int(np.ceil(2 * outer * np.sin(half))) + pad * 2
    H = int(np.ceil(h + outer * (1 - np.cos(half)))) + pad * 2
    ys, xs = np.mgrid[0:H, 0:W].astype(float)
    cx, cy = W / 2.0, H + inner - pad
    dx, dy = xs - cx, cy - ys
    r, theta = np.hypot(dx, dy), np.arctan2(dx, dy)
    sx, sy = w / 2.0 + theta * R, outer - r
    inside = (sx >= 0) & (sx < w - 1) & (sy >= 0) & (sy < h - 1)
    out = np.zeros((H, W, 4), float)
    out[inside] = _sample(src, sx, sy)[inside]
    im = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    return im.crop(im.getbbox())


def shadow(im, offset=(6, 10), blur=10, alpha=150):
    sh = Image.new("RGBA", (im.size[0] + blur * 4, im.size[1] + blur * 4), (0, 0, 0, 0))
    black = Image.new("RGBA", im.size, (0, 0, 0, 255))
    black.putalpha(im.split()[3].point(lambda v: int(v * alpha / 255)))
    sh.alpha_composite(black, (blur * 2 + offset[0], blur * 2 + offset[1]))
    return sh.filter(ImageFilter.GaussianBlur(blur))


def sparks(seed=7, n=26):
    rnd = random.Random(seed)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(n):
        x, y = rnd.gauss(S * 0.60, S * 0.22), rnd.gauss(S * 0.34, S * 0.20)
        if not (6 < x < S - 6 and 6 < y < S - 6):
            continue
        r, a = rnd.uniform(1.4, 4.2), int(rnd.uniform(110, 255))
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, rnd.randint(214, 245), rnd.randint(150, 200), a))
        if r > 2.6:
            L = r * rnd.uniform(3.0, 5.5)
            d.line((x - L, y, x + L, y), fill=(255, 235, 190, int(a * 0.55)))
            d.line((x, y - L, x, y + L), fill=(255, 235, 190, int(a * 0.55)))
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.alpha_composite(layer.filter(ImageFilter.GaussianBlur(2.5)))
    out.alpha_composite(layer)
    return out


def vignette(im, strength=0.8):
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse((-S * 0.15, -S * 0.15, S * 1.15, S * 1.15), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(S / 9))
    dark = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    dark.putalpha(ImageChops.invert(mask).point(lambda v: int(v * strength)))
    out = im.copy()
    out.alpha_composite(dark)
    return out


def gold_edge(width=3, inset=4):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle((inset, inset, S - 1 - inset, S - 1 - inset), radius=22,
                        outline=(214, 170, 92, 230), width=width)
    d.rounded_rectangle((inset + width, inset + width, S - 1 - inset - width, S - 1 - inset - width),
                        radius=18, outline=(70, 46, 18, 120), width=1)
    return layer


def main():
    wordart = _wordart()
    base = ground()

    # the subject on its own layer, so its silhouette can light the ground behind it
    subject = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cards = fit(art("Icon_WildGambit"), 318).rotate(-10, resample=Image.BICUBIC, expand=True)
    subject.alpha_composite(cards, (int(S / 2 - cards.size[0] / 2) + 50,
                                    int(S / 2 - cards.size[1] / 2) - 38))
    book = relight(fit(art("Logo_Almanac"), 250), **LIGHT)
    sh = shadow(book)
    subject.alpha_composite(sh, (int(S / 2 - sh.size[0] / 2 - 40), int(S / 2 - sh.size[1] / 2 + 72)))
    subject.alpha_composite(book, (int(S / 2 - book.size[0] / 2 - 40), int(S / 2 - book.size[1] / 2 + 72)))

    halo_a = subject.split()[3].filter(ImageFilter.MaxFilter(37)).filter(ImageFilter.GaussianBlur(26))
    halo = Image.new("RGBA", (S, S), (255, 186, 96, 0))
    halo.putalpha(halo_a.point(lambda v: int(v * 0.85)))
    base.alpha_composite(halo)
    base.alpha_composite(subject)
    base.alpha_composite(sparks())

    w = wordart.render(FONT, "Azeroth Almanac", wordart.GOLD, size=96)
    w = w.resize((TITLE_WIDTH, max(1, int(w.size[1] * TITLE_WIDTH / w.size[0]))), Image.LANCZOS)
    w = arc(w, span=TITLE_SPAN)
    if w.size[0] > S - 16:
        k = (S - 16) / w.size[0]
        w = w.resize((S - 16, max(1, int(w.size[1] * k))), Image.LANCZOS)
    x, y = (S - w.size[0]) // 2, 8
    pad = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(pad).rectangle((0, y - 14, S, y + w.size[1] + 14), fill=(0, 0, 0, 130))
    base.alpha_composite(pad.filter(ImageFilter.GaussianBlur(18)))
    base.alpha_composite(w, (x, y))

    out = vignette(base)
    out.alpha_composite(gold_edge())
    out.convert("RGB").save(OUT)
    print("%s  %dx%d" % (OUT, S, S))


if __name__ == "__main__":
    main()
