"""(#54) The iron ring's top layers, drawn in code (white, tinted in game):
  Mask_CircleOutside.tga  opaque outside a circle, clear inside: hides what a 3D model draws past the
                          ring (a model frame is square and can't be masked round)
  Ring_Band.tga           a thin hollow ring (the ring itself, drawn over the model)

  python tools/make_ring.py AzerothAlmanac/Media     (128 x 128, 32-bit TGA)
"""
import os, sys
from PIL import Image, ImageDraw

def disc(size, r, scale=4):
    S = size * scale
    m = Image.new("L", (S, S), 0)
    c = S / 2
    ImageDraw.Draw(m).ellipse([c - r * scale, c - r * scale, c + r * scale, c + r * scale], fill=255)
    return m.resize((size, size), Image.LANCZOS)

def main(out):
    N = 128
    inside = disc(N, N / 2 - 0.5)
    outside = inside.point(lambda v: 255 - v)
    white = Image.new("L", (N, N), 255)
    Image.merge("RGBA", (white, white, white, outside)).save(os.path.join(out, "Mask_CircleOutside.tga"))
    outer, inner = disc(N, N / 2 - 0.5), disc(N, N / 2 - 6.5)
    band = Image.frombytes("L", (N, N), bytes(max(0, a - b) for a, b in zip(outer.tobytes(), inner.tobytes())))
    Image.merge("RGBA", (white, white, white, band)).save(os.path.join(out, "Ring_Band.tga"))

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
