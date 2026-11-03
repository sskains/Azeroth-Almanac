"""Builds the Buy Me a Coffee profile picture and cover from the addon's own art.

    python tools/build_buymeacoffee_art.py

Writes CurseForge/BuyMeACoffee/avatar.png (800x800, subject centred: it is shown as a circle) and
cover.jpg (1500x500, the title in the middle: phones crop the edges).
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_gallery_hero as H

OUT_DIR = os.path.join(H.ROOT, "CurseForge", "BuyMeACoffee")


def book(size, angle=-6):
    b = H.key_magenta(Image.open(os.path.join(H.ART, "Logo_Almanac.png")))
    return b.resize((size, size), Image.LANCZOS).rotate(angle, expand=True, resample=Image.BICUBIC)


def backdrop(w, h, darken=0.55):
    bg = Image.open(os.path.join(H.ART, "Zone_ElwynnForest.jpg")).convert("RGB")
    bg = H.cover(bg, w, h).filter(ImageFilter.GaussianBlur(3))
    return Image.blend(bg, Image.new("RGB", (w, h), (14, 10, 6)), darken).convert("RGBA")


def glow(base, box, colour, blur):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(box, fill=colour)
    base.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))


def avatar():
    s = 800
    bg = backdrop(s, s, 0.42)
    glow(bg, (110, 110, 690, 690), (255, 190, 80, 150), 90)
    b = book(560)
    bg.alpha_composite(b, ((s - b.width) // 2, (s - b.height) // 2 + 6))
    bg.convert("RGB").save(os.path.join(OUT_DIR, "avatar.png"), optimize=True)


def cover():
    w, h = 1500, 500
    bg = backdrop(w, h, 0.6)
    vig = Image.new("L", (w, h), 0)
    ImageDraw.Draw(vig).ellipse((-300, -200, w + 300, h + 200), fill=255)
    bg = Image.composite(bg, Image.new("RGBA", (w, h), (6, 4, 2, 255)), vig.filter(ImageFilter.GaussianBlur(120)))
    # the book on the left, two small tiles on the right
    glow(bg, (60, 60, 440, 440), (255, 190, 80, 110), 60)
    b = book(320)
    bg.alpha_composite(b, (60, 90))
    tiles = ["Tab_Creatures.png", "Icon_WildGambit.png"]
    ts = 170
    for i, name in enumerate(tiles):
        art = Image.open(os.path.join(H.ART, name)).convert("RGBA")
        if sum(abs(a - c) for a, c in zip(art.getpixel((4, 4))[:3], (255, 0, 255))) < 40:
            ground = Image.new("RGBA", art.size, (36, 24, 14, 255))
            ground.alpha_composite(H.key_magenta(art))
            art = ground
        art = H.cover(art.convert("RGB"), ts, ts).convert("RGBA")
        if name == "Tab_Places.png":
            px = art.load()
            for y in range(ts):
                for x in range(ts):
                    c = px[x, y]
                    if c[0] > 244 and c[1] > 244 and c[2] > 244:
                        px[x, y] = (30, 20, 12, 255)
        mask = H.rounded_mask((ts, ts), 16)
        tile = Image.new("RGBA", (ts, ts), (0, 0, 0, 0))
        tile.paste(art, (0, 0), mask)
        ImageDraw.Draw(tile).rounded_rectangle((0, 0, ts - 1, ts - 1), 16, outline=(214, 160, 66, 255), width=3)
        x = 1115 + i * 185
        y = 165
        sh = Image.new("RGBA", bg.size, (0, 0, 0, 0))
        sh.paste((0, 0, 0, 200), (x + 4, y + 8), mask)
        bg.alpha_composite(sh.filter(ImageFilter.GaussianBlur(10)))
        bg.alpha_composite(tile, (x, y))
    # the title, centred
    H.gold_text(bg, (715, 175), "Azeroth Almanac", H.font(H.SERIF_B, 72), anchor="mm")
    H.shadow_text(bg, (715, 255), "A free journal and toolkit for WoW Forever", H.font(H.SERIF, 28), H.CREAM, anchor="mm")
    H.shadow_text(bg, (715, 320), "made by Olaris", H.font(H.SERIF_B, 28), H.GOLD, anchor="mm")
    bg.convert("RGB").save(os.path.join(OUT_DIR, "cover.jpg"), quality=95, subsampling=0, optimize=True)


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    avatar()
    cover()
    print(OUT_DIR)
