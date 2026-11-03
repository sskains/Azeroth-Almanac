"""Builds the CurseForge gallery's first image from the addon's own painted art.

    python tools/build_gallery_hero.py

Writes CurseForge/AzerothAlmanac_0_Hero.jpg (1920x1080): the book, the name, and eight tiles for the
big pieces of the addon, over the Elwynn painting. Source pictures are docs/art_source/*. Change the
TILES list to change what it shows.
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "docs", "art_source")
OUT = os.path.join(ROOT, "CurseForge", "AzerothAlmanac_0_Hero.jpg")
W, H = 1920, 1080
GOLD = (255, 214, 102)
GOLD_DARK = (150, 100, 20)
CREAM = (245, 236, 215)

TILES = [
    ("Tab_Places.png", "Journal & Journey", "every first, on a map you walked"),
    ("Tab_Creatures.png", "Bestiary", "creatures, abilities and loot"),
    ("Tab_Characters.png", "Every character", "bags, bank, gear and gold"),
    ("Icon_Merchant.png", "Auction & crafting", "prices, profit, disenchant value"),
    ("Tab_Quests.png", "Quests & map arrow", "chains, targets, and where to go"),
    ("Icon_Training.png", "Talent Planner", "plan and stage any build"),
    ("Icon_Flight_Gryphon.png", "Flight timers", "and a gryphon with opinions"),
    ("Icon_WildGambit.png", "Card games", "Wild Gambit, Gem Match & more"),
]


def font(names, size):
    for n in names:
        for d in (r"C:\Windows\Fonts", "/usr/share/fonts/truetype/dejavu"):
            p = os.path.join(d, n)
            if os.path.exists(p):
                return ImageFont.truetype(p, size)
    return ImageFont.load_default()


SERIF_B = ["georgiab.ttf", "constanb.ttf", "cambriab.ttf", "DejaVuSerif-Bold.ttf"]
SERIF = ["georgia.ttf", "constan.ttf", "cambria.ttc", "DejaVuSerif.ttf"]


def key_magenta(im):
    """the art on a magenta ground -> transparent, with a soft edge"""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            d = (255 - r) + g + (255 - b)  # 0 at pure magenta
            if d < 110:
                px[x, y] = (r, g, b, 0)
            elif d < 230:
                px[x, y] = (r, g, b, int(255 * (d - 110) / 120))
    # a hair in from the edge, so no magenta fringe survives
    a = im.getchannel("A").filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(0.8))
    im.putalpha(a)
    return im


def cover(im, w, h):
    s = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    x, y = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))


def rounded_mask(size, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), r, fill=255)
    return m


def shadow_text(base, xy, text, fnt, fill, anchor="la", stroke=0, glow=True):
    d = ImageDraw.Draw(base)
    if glow:
        layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).text((xy[0] + 3, xy[1] + 5), text, font=fnt, fill=(0, 0, 0, 230), anchor=anchor, stroke_width=stroke + 2, stroke_fill=(0, 0, 0, 230))
        layer = layer.filter(ImageFilter.GaussianBlur(5))
        base.alpha_composite(layer)
    d.text(xy, text, font=fnt, fill=fill, anchor=anchor, stroke_width=stroke, stroke_fill=(40, 20, 0))


def gold_text(base, xy, text, fnt, anchor="la"):
    """gold gradient fill with a dark outline"""
    shadow_text(base, xy, text, fnt, GOLD_DARK, anchor, stroke=4)
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).text(xy, text, font=fnt, fill=255, anchor=anchor)
    grad = Image.new("RGBA", base.size)
    gd = ImageDraw.Draw(grad)
    bbox = mask.getbbox()
    top, bot = bbox[1], bbox[3]
    for y in range(top, bot + 1):
        t = (y - top) / max(1, bot - top)
        c = (255, int(246 - 70 * t), int(170 - 120 * t))
        gd.line((0, y, base.width, y), fill=c + (255,))
    base.paste(grad, (0, 0), ImageChops.multiply(mask, mask))


def main():
    # background: the Elwynn painting, softened and darkened, with a vignette
    bg = Image.open(os.path.join(ART, "Zone_ElwynnForest.jpg")).convert("RGB")
    bg = cover(bg, W, H).filter(ImageFilter.GaussianBlur(3))
    bg = Image.blend(bg, Image.new("RGB", (W, H), (14, 10, 6)), 0.58).convert("RGBA")
    vig = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vig).ellipse((-380, -300, W + 380, H + 300), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(220))
    bg = Image.composite(bg, Image.new("RGBA", (W, H), (6, 4, 2, 255)), vig)

    # left: the book, the name, the promise
    book = key_magenta(Image.open(os.path.join(ART, "Logo_Almanac.png")))
    book = book.resize((420, 420), Image.LANCZOS).rotate(-6, expand=True, resample=Image.BICUBIC)
    glow = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((20, 140, 520, 640), fill=(255, 190, 80, 90))
    bg.alpha_composite(glow.filter(ImageFilter.GaussianBlur(60)))
    bg.alpha_composite(book, (70, 130))

    gold_text(bg, (70, 610), "Azeroth", font(SERIF_B, 96))
    gold_text(bg, (70, 705), "Almanac", font(SERIF_B, 96))
    shadow_text(bg, (76, 835), "Everything your characters", font(SERIF, 30), CREAM)
    shadow_text(bg, (76, 876), "discover, plus the helpers you'd", font(SERIF, 30), CREAM)
    shadow_text(bg, (76, 917), "otherwise install separately.", font(SERIF, 30), CREAM)

    # right: eight tiles
    cols, tw, th, gap = 4, 300, 300, 22
    cap_h = 92
    x0 = W - 60 - (cols * tw + (cols - 1) * gap)
    y0 = 118
    f_name, f_sub = font(SERIF_B, 27), font(SERIF, 19)
    for i, (file, name, sub) in enumerate(TILES):
        col, row = i % cols, i // cols
        x, y = x0 + col * (tw + gap), y0 + row * (th + cap_h + gap + 6)
        art = Image.open(os.path.join(ART, file)).convert("RGBA")
        if file == "Tab_Places.png":  # the painting has white corners outside its rounded edge
            px = art.load()
            for yy in range(art.height):
                for xx in range(art.width):
                    c = px[xx, yy]
                    if c[0] > 244 and c[1] > 244 and c[2] > 244:
                        px[xx, yy] = (30, 20, 12, 255)
        if art.getpixel((4, 4))[:3] == (255, 0, 255) or sum(abs(a - b) for a, b in zip(art.getpixel((4, 4))[:3], (255, 0, 255))) < 40:
            keyed = key_magenta(art)
            ground = Image.new("RGBA", art.size, (36, 24, 14, 255))
            glow = Image.new("RGBA", art.size, (0, 0, 0, 0))
            ImageDraw.Draw(glow).ellipse((art.width * 0.1, art.height * 0.1, art.width * 0.9, art.height * 0.9), fill=(120, 70, 160, 120))
            ground.alpha_composite(glow.filter(ImageFilter.GaussianBlur(art.width // 6)))
            ground.alpha_composite(keyed)
            art = ground
        tile = cover(art.convert("RGB"), tw, th).convert("RGBA")
        card = Image.new("RGBA", (tw, th + cap_h), (22, 15, 9, 255))
        card.paste(tile, (0, 0))
        # caption plate
        d = ImageDraw.Draw(card)
        d.rectangle((0, th, tw, th + cap_h), fill=(30, 21, 12, 255))
        d.line((0, th, tw, th), fill=(200, 150, 60, 255), width=2)
        d.text((tw // 2, th + 30), name, font=f_name, fill=GOLD, anchor="mm")
        d.text((tw // 2, th + 64), sub, font=f_sub, fill=(214, 200, 170), anchor="mm", )
        mask = rounded_mask(card.size, 16)
        sh = Image.new("RGBA", bg.size, (0, 0, 0, 0))
        sh.paste((0, 0, 0, 200), (x + 4, y + 10), mask)
        bg.alpha_composite(sh.filter(ImageFilter.GaussianBlur(12)))
        framed = Image.new("RGBA", card.size, (0, 0, 0, 0))
        framed.paste(card, (0, 0), mask)
        ImageDraw.Draw(framed).rounded_rectangle((0, 0, card.width - 1, card.height - 1), 16, outline=(214, 160, 66, 255), width=3)
        bg.alpha_composite(framed, (x, y))

    # bottom right: the rest, and how to open it
    ybar = y0 + 2 * (th + cap_h + gap + 6) - 4
    shadow_text(bg, (W - 60, ybar + 6), "+ item tooltips  ·  gathering  ·  spell ranks  ·  group tools  ·  and more", font(SERIF, 25), (230, 215, 180), anchor="ra")
    shadow_text(bg, (W - 60, ybar + 46), "Made for WoW Forever   —   press  Shift+J  or type  /aa", font(SERIF_B, 27), GOLD, anchor="ra")

    # a JPEG at 95% with full colour detail: well under CurseForge's 2 MB limit (the PNG was just over)
    bg.convert("RGB").save(OUT, quality=95, subsampling=0, optimize=True)
    print(OUT)


if __name__ == "__main__":
    main()
