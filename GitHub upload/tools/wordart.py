"""
Azeroth Almanac - dungeon and raid names as word art (0.69.0, #31).

Renders every name in the Wild Gambit dungeon list (QoL/WildGambitDungeons.lua) in the LifeCraft font
(dafont, donationware, by Eliot Truelove; credit in AzerothAlmanac/Licenses/LifeCraft.txt): a gold
gradient, a bevel lit from the top left, a dark bronze outline and a soft shadow. Raids are a deeper
red-gold. The font file is not shipped: only the finished pictures are.

Usage: python wordart.py <LifeCraft_Font.ttf> [<addon folder>]
  (default addon folder: ../AzerothAlmanac next to this tool)

Writes:
  Media/DungeonNames_<n>.tga        the names packed onto 1024-wide sheets, up to 2048 tall (transparent)
  Data/DungeonNames.lua             ns.DungeonNames[lower-case name] = { sheet, left, right, top, bottom, w, h }
                                    (texture coordinates, and the picture's size in pixels)
Re-run after adding a dungeon; then a full game restart (new textures).
"""
import os, re, sys, struct, datetime
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SIZE = 60          # letter size in pixels (sharp at the card's plaque and the page header)
SHEET_W = 1024
# names the game uses that differ from the list's (GetInstanceInfo), drawn too
ALIASES = {"Blackrock Spire": False, "Sunken Temple": False}

GOLD = ((255, 244, 190), (240, 190, 70), (150, 85, 20))
RAID = ((255, 222, 170), (232, 128, 52), (128, 36, 14))


def write_tga(img, path):
    img = img.convert("RGBA")
    w, h = img.size
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    with open(path, "wb") as f:
        f.write(hdr + img.transpose(Image.FLIP_TOP_BOTTOM).tobytes("raw", "BGRA"))


def lines_of(name):
    """long names on two lines, split at the space nearest the middle"""
    if len(name) <= 14 or " " not in name:
        return [name]
    spaces = [i for i, ch in enumerate(name) if ch == " "]
    cut = min(spaces, key=lambda i: abs(i - len(name) / 2))
    return [name[:cut], name[cut + 1:]]


def render(font_path, name, colours, size=SIZE):
    f = ImageFont.truetype(font_path, size)
    rows = lines_of(name)
    pad = size // 3
    gap = int(size * 0.08)
    boxes = [f.getbbox(r) for r in rows]
    tw = max(b[2] - b[0] for b in boxes)
    lh = max(b[3] - b[1] for b in boxes)
    W, H = tw + pad * 2, lh * len(rows) + gap * (len(rows) - 1) + pad * 2
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    for i, (r, b) in enumerate(zip(rows, boxes)):
        x = pad + (tw - (b[2] - b[0])) // 2 - b[0]
        y = pad + i * (lh + gap) - b[1]
        d.text((x, y), r, font=f, fill=255)
    a = np.asarray(m).astype(float) / 255
    # the bevel: light from the top left, from the slope of the blurred letters
    bl = np.asarray(m.filter(ImageFilter.GaussianBlur(size * 0.035))).astype(float) / 255
    gy, gx = np.gradient(bl)
    shade = np.clip(0.5 + (-gx * 0.6 - gy * 1.0) * size * 0.075, 0, 1)
    # gold down each line: pale at the top, deep at the foot
    ys = np.zeros((H, W))
    for i in range(len(rows)):
        top = pad + i * (lh + gap)
        for y in range(max(0, top - gap), min(H, top + lh + gap)):
            ys[y, :] = np.clip((y - top) / max(1, lh), 0, 1)
    top_c, mid_c, bot_c = (np.array(c, float) for c in colours)
    t = ys[..., None]
    g = np.where(t < 0.5, top_c + (mid_c - top_c) * (t / 0.5), mid_c + (bot_c - mid_c) * ((t - 0.5) / 0.5))
    hl = shade[..., None] - 0.5
    col = np.clip(g + hl * np.where(hl > 0, 300, 240), 0, 255)

    def dil(img, r):
        return img.filter(ImageFilter.MaxFilter(r * 2 + 1))
    # (small use: a thicker outline than the large sample, so the letters hold at plaque size)
    o1 = np.asarray(dil(m, max(2, size // 20))).astype(float) / 255
    o2 = np.asarray(dil(m, max(3, size // 12)).filter(ImageFilter.GaussianBlur(size * 0.03))).astype(float) / 255
    sh = np.asarray(dil(m, max(2, size // 20)).filter(ImageFilter.GaussianBlur(size * 0.06))).astype(float) / 255
    sh = np.roll(np.roll(sh, size // 18, 0), size // 30, 1)
    out = np.zeros((H, W, 4))

    def over(rgb, al):
        al = al[..., None]
        out[..., :3] = rgb * al + out[..., :3] * (1 - al)
        out[..., 3:] = al + out[..., 3:] * (1 - al)
    over(np.zeros((H, W, 3)), sh * 0.85)
    over(np.ones((H, W, 3)) * np.array([70, 38, 10]), np.clip(o2, 0, 1) * 0.9)
    over(np.ones((H, W, 3)) * np.array([40, 20, 5]), o1)
    over(col, a)
    # (colours stored straight, not premultiplied: the game blends with alpha)
    rgb = np.where(out[..., 3:] > 0, out[..., :3] / np.maximum(out[..., 3:], 1e-6), 0)
    img = Image.fromarray(np.dstack([rgb, out[..., 3] * 255]).astype(np.uint8), "RGBA")
    return img.crop(img.getbbox())


def dungeon_names(addon):
    src = open(os.path.join(addon, "QoL", "WildGambitDungeons.lua"), encoding="utf-8").read()
    names = {}
    for line in src.splitlines():
        mt = re.search(r'dungeon = "([^"]+)"', line)
        if mt:
            names[mt.group(1)] = "raid = true" in line
    for n, raid in ALIASES.items():
        names.setdefault(n, raid)
    return names


def main(font_path, addon):
    names = dungeon_names(addon)
    pics = [(n, render(font_path, n, RAID if raid else GOLD)) for n, raid in sorted(names.items())]
    # shelf packing onto 1024-wide sheets, at most 2048 tall
    sheets, placed = [], {}
    x = y = shelf = 0
    cur = []
    for n, img in sorted(pics, key=lambda p: -p[1].height):
        w, h = img.size
        if x + w + 2 > SHEET_W:
            x, y, shelf = 0, y + shelf + 2, 0
        if y + h + 2 > 2048:
            sheets.append((cur, y + shelf))
            cur, x, y, shelf = [], 0, 0, 0
        cur.append((n, img, x, y))
        x += w + 2
        shelf = max(shelf, h)
    sheets.append((cur, y + shelf))
    lines = []
    for i, (items, used) in enumerate(sheets, 1):
        sh = 16
        while sh < used:
            sh *= 2
        sheet = Image.new("RGBA", (SHEET_W, sh), (0, 0, 0, 0))
        for n, img, px, py in items:
            sheet.alpha_composite(img, (px, py))
            w, h = img.size
            key = '"' + n.lower().replace("\\", "\\\\").replace('"', '\\"') + '"'
            lines.append(f"\t[{key}] = {{ {i}, {px / SHEET_W:.5f}, {(px + w) / SHEET_W:.5f}, {py / sh:.5f}, {(py + h) / sh:.5f}, {w}, {h} }},")
        write_tga(sheet, os.path.join(addon, "Media", f"DungeonNames_{i}.tga"))
        print(f"DungeonNames_{i}.tga: {SHEET_W} x {sh}, {len(items)} names")
    with open(os.path.join(addon, "Data", "DungeonNames.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- Generated by tools/wordart.py on {datetime.date.today()}: dungeon and raid names as word art in the\n")
        f.write("-- LifeCraft font (Eliot Truelove; Licenses\\LifeCraft.txt). Do not edit by hand.\n")
        f.write("-- [lower-case name] = { sheet (Media\\DungeonNames_<n>), left, right, top, bottom, width, height }\n")
        f.write("local _, ns = ...\nns.DungeonNames = {\n" + "\n".join(lines) + "\n}\n")
    print(f"{len(pics)} names")


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "..", "AzerothAlmanac"))
