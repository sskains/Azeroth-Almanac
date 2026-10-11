"""The Journey's playback buttons: Play, Pause, Slower, Faster, white with a dark outline so the
game can tint them (gold when on, grey otherwise), like the Cards / List view buttons.

  python tools/make_play_icons.py AzerothAlmanac/Media
  (Journey_Play.tga, Journey_Pause.tga, Journey_Slower.tga, Journey_Faster.tga,
   Journey_Larger.tga, Journey_Smaller.tga, 32 x 32)
Stand-ins drawn in code; painted ones can replace them (same names and size).
"""
import os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 256

def finish(draw, out):
    mask = Image.new("L", (S, S), 0)
    draw(ImageDraw.Draw(mask))
    outline = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    outline.putalpha(mask.filter(ImageFilter.MaxFilter(15)).point(lambda v: int(v * 0.85)))
    shade = Image.linear_gradient("L").resize((S, S)).point(lambda v: 255 - int(v * 0.22))
    body = Image.merge("RGBA", (shade, shade, shade, mask))
    Image.alpha_composite(outline, body).resize((32, 32), Image.LANCZOS).save(out)

def tri(d, x0, x1, y0, y1, right=True):
    if right: d.polygon([(x0, y0), (x1, (y0 + y1) // 2), (x0, y1)], fill=255)
    else: d.polygon([(x1, y0), (x0, (y0 + y1) // 2), (x1, y1)], fill=255)

def main(folder):
    finish(lambda d: tri(d, 70, 206, 40, 216), os.path.join(folder, "Journey_Play.tga"))
    finish(lambda d: (d.rounded_rectangle((58, 44, 110, 212), 10, fill=255), d.rounded_rectangle((146, 44, 198, 212), 10, fill=255)),
           os.path.join(folder, "Journey_Pause.tga"))
    finish(lambda d: (tri(d, 24, 128, 60, 196, False), tri(d, 120, 224, 60, 196, False)), os.path.join(folder, "Journey_Slower.tga"))
    finish(lambda d: (tri(d, 32, 136, 60, 196), tri(d, 128, 232, 60, 196)), os.path.join(folder, "Journey_Faster.tga"))

def corners(d, out):
    # two arrows on the diagonal: out to the top right and bottom left corners (Larger), or in (Smaller)
    w = 34
    for sx, sy in ((1, -1), (-1, 1)):
        cx, cy = S // 2, S // 2
        tip = (cx + sx * 104, cy + sy * 104) if out else (cx + sx * 22, cy + sy * 22)
        tail = (cx + sx * 22, cy + sy * 22) if out else (cx + sx * 104, cy + sy * 104)
        d.line([tail, tip], fill=255, width=w)
        # the head: a right angle at the tip, its arms back along x and y
        bx, by = (-sx, -sy) if out else (sx, sy)
        L = 78
        d.polygon([tip, (tip[0] + bx * L, tip[1]), (tip[0], tip[1] + by * L)], fill=255)

def more(folder):
    finish(lambda d: corners(d, True), os.path.join(folder, "Journey_Larger.tga"))
    finish(lambda d: corners(d, False), os.path.join(folder, "Journey_Smaller.tga"))

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
    more(sys.argv[1] if len(sys.argv) > 1 else ".")
