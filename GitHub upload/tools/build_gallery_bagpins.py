"""Builds the CurseForge gallery image for Bag pins, in the gallery hero's style (build_gallery_hero.py).

    python tools/build_gallery_bagpins.py

Writes CurseForge/AzerothAlmanac_BagPins.jpg (1920x1080): the same bag before and after the game's
Cleanup, the other items sorted but the pinned ones (gold glow, a pin badge) still in their slots,
with a how-to strip under it. The items are the addon's own paintings standing in for bag items
(docs/art_source); change BAG to change what's where.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

from build_gallery_hero import ART, ROOT, W, H, GOLD, CREAM, font, key_magenta, cover, rounded_mask, shadow_text, gold_text, SERIF, SERIF_B

OUT = os.path.join(ROOT, "CurseForge", "AzerothAlmanac_BagPins.jpg")
COLS, ROWS = 4, 4
SLOT, GAP = 118, 14

# what's in the bag before Cleanup, slot by slot (None: empty); "*" marks a pinned item
BAG = [
    "*Icon_Fishing", "Spell_Barkskin", None, "*Icon_Flight_Gryphon",
    "Tab_Gathering", None, "Spell_Polymorph", "Tab_Recipes",
    None, "Spell_FreezingTrap", "Tab_Items", None,
    "*GemMatch_Pouch", "Spell_DivineShield", None, "Tab_Quests",
]
MAGENTA = {"GemMatch_Pouch"}  # painted on magenta: keyed out


def item_art(name, size):
    im = Image.open(os.path.join(ART, name + ".png"))
    if name in MAGENTA:
        im = key_magenta(im)
        back = Image.new("RGBA", im.size, (52, 36, 22, 255))
        back.alpha_composite(im)
        im = back
    return cover(im.convert("RGBA"), size, size)


def after_cleanup(bag):
    """the game's Cleanup sorts the rest towards the front; pinned items keep their slots"""
    loose = sorted(n for n in bag if n and not n.startswith("*"))
    out = []
    for n in bag:
        if n and n.startswith("*"):
            out.append(n)
        else:
            out.append(loose.pop(0) if loose else None)
    return out


def pin_badge(size):
    """a red map pin on a gold disc, drawn (no game art in the repo)"""
    s = size * 4  # drawn large, scaled down for smooth edges
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((0, 0, s - 1, s - 1), fill=(60, 36, 8, 255))
    d.ellipse((s * 0.05, s * 0.05, s * 0.95, s * 0.95), fill=(236, 186, 74, 255))
    d.ellipse((s * 0.12, s * 0.12, s * 0.88, s * 0.88), fill=(96, 58, 16, 255))
    cx = s / 2
    head_r = s * 0.2
    head_y = s * 0.4
    d.polygon([(cx - head_r * 0.82, head_y + head_r * 0.55), (cx + head_r * 0.82, head_y + head_r * 0.55), (cx, s * 0.82)], fill=(196, 34, 34, 255))
    d.ellipse((cx - head_r, head_y - head_r, cx + head_r, head_y + head_r), fill=(214, 42, 42, 255))
    d.ellipse((cx - head_r * 0.55, head_y - head_r * 0.62, cx - head_r * 0.05, head_y - head_r * 0.12), fill=(255, 170, 160, 255))
    return im.resize((size, size), Image.LANCZOS)


def bag_panel(items, title):
    pad, head = 26, 64
    pw = COLS * SLOT + (COLS - 1) * GAP + 2 * pad
    ph = ROWS * SLOT + (ROWS - 1) * GAP + 2 * pad + head
    panel = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    # the bag: dark leather with a gold rim
    body = Image.new("RGBA", (pw, ph), (30, 21, 13, 238))
    panel.paste(body, (0, 0), rounded_mask((pw, ph), 22))
    d = ImageDraw.Draw(panel)
    d.rounded_rectangle((1, 1, pw - 2, ph - 2), 22, outline=(196, 150, 70, 255), width=3)
    d.rounded_rectangle((7, 7, pw - 8, ph - 8), 18, outline=(90, 62, 28, 255), width=1)
    shadow_text(panel, (pw // 2, head // 2 + 14), title, font(SERIF_B, 36), CREAM, anchor="mm", glow=False)
    badge = pin_badge(46)
    for i, name in enumerate(items):
        x = pad + (i % COLS) * (SLOT + GAP)
        y = head + pad + (i // COLS) * (SLOT + GAP)
        pinned = bool(name) and name.startswith("*")
        if pinned:
            glow = Image.new("RGBA", panel.size, (0, 0, 0, 0))
            ImageDraw.Draw(glow).rounded_rectangle((x - 9, y - 9, x + SLOT + 9, y + SLOT + 9), 18, fill=(255, 200, 80, 200))
            panel.alpha_composite(glow.filter(ImageFilter.GaussianBlur(9)))
        # the slot: sunk, dark, a thin bevel
        d.rounded_rectangle((x, y, x + SLOT, y + SLOT), 12, fill=(12, 9, 6, 255), outline=(70, 52, 30, 255), width=2)
        if name:
            art = item_art(name.lstrip("*"), SLOT - 10)
            panel.paste(art, (x + 5, y + 5), rounded_mask(art.size, 9))
            d.rounded_rectangle((x + 4, y + 4, x + SLOT - 4, y + SLOT - 4), 10,
                                outline=(255, 214, 102, 255) if pinned else (110, 84, 46, 255), width=4 if pinned else 2)
        if pinned:
            panel.alpha_composite(badge, (x + SLOT - 34, y - 12))
    return panel


def arrow(w, h):
    """the Cleanup arrow between the bags"""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    mid = h // 2
    d.polygon([(0, mid - 16), (w - 48, mid - 16), (w - 48, mid - 40), (w, mid), (w - 48, mid + 40), (w - 48, mid + 16), (0, mid + 16)],
              fill=(236, 186, 74, 255), outline=(110, 70, 18, 255))
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh.alpha_composite(im.filter(ImageFilter.GaussianBlur(6)), (3, 5))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(Image.eval(sh, lambda v: v // 2))
    out.alpha_composite(im)
    return out


def main():
    bg = Image.open(os.path.join(ART, "Zone_Ironforge.jpg")).convert("RGB")
    bg = cover(bg, W, H).filter(ImageFilter.GaussianBlur(4))
    bg = Image.blend(bg, Image.new("RGB", (W, H), (14, 10, 6)), 0.62).convert("RGBA")
    vig = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vig).ellipse((-380, -300, W + 380, H + 300), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(220))
    dark = Image.new("RGBA", (W, H), (6, 4, 2, 255))
    base = Image.composite(bg, dark, vig)

    gold_text(base, (W // 2, 92), "Bag Pins", font(SERIF_B, 112), anchor="mm")
    shadow_text(base, (W // 2, 184), "Pin an item to a bag slot. Cleanup sorts the rest; your pins stay put.", font(SERIF, 38), CREAM, anchor="mm")

    left = bag_panel(BAG, "Before Cleanup")
    right = bag_panel(after_cleanup(BAG), "After Cleanup")
    top = 236
    gap = 230
    lx = (W - (left.width + gap + right.width)) // 2
    rx = lx + left.width + gap
    for panel, x in ((left, lx), (right, rx)):
        sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        sh.alpha_composite(Image.new("RGBA", panel.size, (0, 0, 0, 170)), (x + 8, top + 14))
        base.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14)))
        base.alpha_composite(panel, (x, top))
    a = arrow(gap - 60, 120)
    ay = top + left.height // 2 - 60
    base.alpha_composite(a, (lx + left.width + 30, ay))
    shadow_text(base, (lx + left.width + gap // 2, ay - 18), "Cleanup", font(SERIF_B, 34), GOLD, anchor="mm")

    # how to, under the bags
    steps = ["Alt+Click an item to pin it", "Press Cleanup as usual", "Pinned items hop back to their slot"]
    y = top + left.height + 62
    f = font(SERIF_B, 34)
    sep = "   ·   "
    line = sep.join(steps)
    shadow_text(base, (W // 2, y), line, f, GOLD, anchor="mm")
    shadow_text(base, (W // 2, y + 52), "Alt+Click again to unpin  ·  Settings › Bags and bank › Bag pins  ·  per character",
                font(SERIF, 28), CREAM, anchor="mm")
    shadow_text(base, (W - 40, H - 34), "Azeroth Almanac  —  made for WoW Forever", font(SERIF, 26), (220, 205, 175), anchor="rm")

    base.convert("RGB").save(OUT, "JPEG", quality=95, optimize=True)
    print(OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    main()
