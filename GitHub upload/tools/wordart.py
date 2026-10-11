"""
Azeroth Almanac - dungeon and raid names as word art (0.69.0, #31).

Renders every name in the Wild Gambit dungeon list (QoL/WildGambitDungeons.lua) in capitals, in the
Marcellus font (Astigmatic / Brian J. Bonislawsky, SIL Open Font License 1.1; credit in
AzerothAlmanac/Licenses/Marcellus.txt; Shannon's pick, 2026-10-10, over Friz Quadrata which we can't
ship pictures of): a smooth gold gradient (pale at the top of the letters, deep amber at the foot), a
dark bronze outline, a soft shadow below, and worn gilding (chipped edges, nicks, scratches, grime).
Anything for more than five players (the raids, and Upper Blackrock Spire's ten) is a deep orange.
The font file is not shipped: only the finished pictures are. (Until 2026-10-10: LifeCraft, with a bevel.)

Usage: python wordart.py <Marcellus-Regular.ttf or .woff> [<addon folder>]
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
DISTRESS = True    # (0.69.1) weathered, abandoned gilding (see distress)
# names the game uses that differ from the list's (GetInstanceInfo), drawn too
ALIASES = {"Blackrock Spire": False, "Sunken Temple": False}

GOLD = ((255, 248, 205), (255, 206, 90), (178, 100, 24))
RAID = ((255, 226, 170), (255, 140, 36), (160, 52, 8))     # deep orange: more than five players
BIG = {"Upper Blackrock Spire"}                            # (not a raid in the list, but ten players)


def write_tga(img, path):
    img = img.convert("RGBA")
    w, h = img.size
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    with open(path, "wb") as f:
        f.write(hdr + img.transpose(Image.FLIP_TOP_BOTTOM).tobytes("raw", "BGRA"))


def lines_of(name):
    """long names on two lines, split at the space nearest the middle"""
    if len(name) <= 11 or " " not in name:
        return [name]
    spaces = [i for i, ch in enumerate(name) if ch == " "]
    cut = min(spaces, key=lambda i: abs(i - len(name) / 2))
    return [name[:cut], name[cut + 1:]]


def render(font_path, name, colours, size=SIZE):
    f = ImageFont.truetype(font_path, size)
    rows = lines_of(name.upper())
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
    # (2026-10-10: no bevel, the smooth gradient alone, as in the mock-up Shannon chose)
    col = np.clip(g, 0, 255)

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
    if DISTRESS:
        col, a = distress(name, col, a, size)
    over(col, a)
    # (colours stored straight, not premultiplied: the game blends with alpha)
    rgb = np.where(out[..., 3:] > 0, out[..., :3] / np.maximum(out[..., 3:], 1e-6), 0)
    img = Image.fromarray(np.dstack([rgb, out[..., 3] * 255]).astype(np.uint8), "RGBA")
    return img.crop(img.getbbox())


def distress(name, col, a, size):
    """(2026-10-10) worn gilding, as in the mock-up: chips bitten out of the letters' edges, a few nicks
    and fine scratches through them, and soft blotches of grime with a fine grain. Seeded by the name,
    so a re-run gives the same marks, and each name wears differently."""
    import zlib
    from scipy import ndimage
    H, W = a.shape
    rng = np.random.default_rng(zlib.crc32(name.encode()))
    def noise(sig):
        n = ndimage.gaussian_filter(rng.random((H, W)), sig)
        return (n - n.min()) / max(1e-6, n.max() - n.min())
    # chips on the rim (the outline shows through)
    inner = ndimage.grey_erosion(a, size=(max(3, size // 15),) * 2)
    rim = np.clip(a - inner, 0, 1)
    chips = (noise(size * 0.05) < 0.28).astype(float)
    a = a * (1 - rim * chips)
    # nicks and scratches
    sc = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(sc)
    for _ in range(max(3, W * H // 9000)):
        x0, y0 = rng.uniform(0, W), rng.uniform(0, H)
        ln, ang = rng.uniform(size * 0.12, size * 0.35), rng.uniform(-0.6, 0.6)
        d.line((x0, y0, x0 + np.cos(ang) * ln, y0 + np.sin(ang) * ln), fill=255, width=int(rng.choice([1, 2])))
    for _ in range(max(6, W * H // 1500)):
        x0, y0, r = rng.uniform(0, W), rng.uniform(0, H), float(rng.choice([1, 1, 2]))
        d.ellipse((x0 - r, y0 - r, x0 + r, y0 + r), fill=255)
    a = a * (1 - 0.85 * np.asarray(sc).astype(float) / 255)
    # grime and grain (a gentle darkening, never below about three quarters)
    k = (0.76 + 0.24 * noise(size * 0.12)) * (0.88 + 0.12 * noise(0.8))
    col = col * k[..., None]
    return np.clip(col, 0, 255), np.clip(a, 0, 1)


def dungeon_names(addon):
    src = open(os.path.join(addon, "QoL", "WildGambitDungeons.lua"), encoding="utf-8").read()
    names = {}
    for line in src.splitlines():
        mt = re.search(r'dungeon = "([^"]+)"', line)
        if mt:
            names[mt.group(1)] = "raid = true" in line or mt.group(1) in BIG
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
        f.write("-- Marcellus font (Astigmatic, SIL OFL 1.1; Licenses\\Marcellus.txt), capitals, worn gilding; more than five\n")
        f.write("-- players in deep orange. Do not edit by hand.\n")
        f.write("-- [lower-case name] = { sheet (Media\\DungeonNames_<n>), left, right, top, bottom, width, height }\n")
        f.write("local _, ns = ...\nns.DungeonNames = {\n" + "\n".join(lines) + "\n}\n")
    print(f"{len(pics)} names")


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "..", "AzerothAlmanac"))
