"""(#55) The upgrade arrow: a white up arrow with a dark outline, shaded darker toward the bottom, so
the game can tint it (green for you, gold for another character) in texture markup.

  python tools/make_arrow.py AzerothAlmanac/Media/Arrow_Upgrade.tga     (64 x 64, 32-bit TGA)
A stand-in drawn in code; a painted one can replace it (same name and size).
"""
import sys
from PIL import Image, ImageDraw, ImageFilter

def main(out):
    S = 256
    pts = [(S * .5, S * .08), (S * .90, S * .52), (S * .64, S * .52), (S * .64, S * .92), (S * .36, S * .92), (S * .36, S * .52), (S * .10, S * .52)]
    outline = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(outline).polygon(pts, fill=(20, 14, 6, 255))
    outline = outline.filter(ImageFilter.MaxFilter(17))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    shade = Image.linear_gradient("L").resize((S, S)).point(lambda v: 255 - int(v * 0.30))
    body = Image.merge("RGBA", (shade, shade, shade, mask))
    Image.alpha_composite(outline, body).resize((64, 64), Image.LANCZOS).save(out)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Arrow_Upgrade.tga")
