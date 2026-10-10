"""The Cards / List view buttons (Creatures, Items): a 2 x 2 grid of tiles and three list lines,
white with a dark outline so the game can tint them (gold when picked, grey otherwise).

  python tools/make_view_icons.py AzerothAlmanac/Media     (View_Cards.tga, View_List.tga, 32 x 32)
Stand-ins drawn in code; painted ones can replace them (same names and size).
"""
import os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 256

def finish(shapes, out):
    mask = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(mask)
    for kind, box in shapes:
        d.rounded_rectangle(box, radius=kind, fill=255)
    outline = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    outline.putalpha(mask.filter(ImageFilter.MaxFilter(15)).point(lambda v: int(v * 0.85)))
    shade = Image.linear_gradient("L").resize((S, S)).point(lambda v: 255 - int(v * 0.22))
    body = Image.merge("RGBA", (shade, shade, shade, mask))
    Image.alpha_composite(outline, body).resize((32, 32), Image.LANCZOS).save(out)

def main(folder):
    g, m = 20, 26
    a, b = 28, S - 28
    half = (b - a - g) // 2
    tiles = []
    for r in range(2):
        for c in range(2):
            x0 = a + c * (half + g); y0 = a + r * (half + g)
            tiles.append((m, (x0, y0, x0 + half, y0 + half)))
    finish(tiles, os.path.join(folder, "View_Cards.tga"))
    rows = []
    h, gap = 40, 30
    top = (S - (3 * h + 2 * gap)) // 2
    for i in range(3):
        y = top + i * (h + gap)
        rows.append((10, (a, y, a + h, y + h)))
        rows.append((10, (a + h + 22, y, b, y + h)))
    finish(rows, os.path.join(folder, "View_List.tga"))

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
