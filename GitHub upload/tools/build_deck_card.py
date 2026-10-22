"""
Azeroth Almanac - cut the painted deck card out of the felt (Media/Deck_Card.tga).

The card lying on the table's top left corner is painted into Media/Background_Pick, not drawn as
a frame, so it cannot light up when you point at it. This lifts exactly that card out of the felt
onto its own small texture. The UI lays it back over the painting, pixel for pixel, invisible until
you hover - then it brightens, so the painted card itself is what highlights.

Keeping it a crop of the original matters: anything redrawn would sit slightly off the painting
underneath and show as a double edge.

The felt is nine sliced with 250 x 210 corners, so that corner is drawn at its own size and the
card's place in the art is its place on screen.

Output: an uncompressed 32-bit TGA, 256x256 (the card sits at its top left).

Usage: python build_deck_card.py <Media dir>
"""
import sys, os
from PIL import Image, ImageFilter

CARD = (88, 48, 246, 205)      # the card in Background_Pick, with a little room for its shadow
OUT = 256                      # power-of-two canvas


def is_felt(r, g, b):
    """The green cloth the card lies on: green clearly ahead of red and blue."""
    return g > r + 8 and g > b + 8 and g < 150


def is_wood(r, g, b):
    """The table's dark wooden edge, which creeps into the top left of the crop."""
    return r < 95 and g < 80 and b < 65


def build(media):
    src = Image.open(os.path.join(media, 'Background_Pick.tga')).convert('RGBA')
    crop = src.crop(CARD)
    w, h = crop.size
    px = crop.load()

    # Alpha: the card only. The table is removed by flooding in from the edges rather than by
    # testing each pixel on its own - the card's dark red field reads as "wood" to any per-pixel
    # test, and testing alone cut the middle out of the card. Flooding only removes table that the
    # border can reach, so anything enclosed by the card's edge survives whatever colour it is.
    mask = Image.new('L', (w, h), 255)
    mp = mask.load()
    seen = bytearray(w * h)
    stack = []
    for x in range(w):
        stack.append((x, 0))
        stack.append((x, h - 1))
    for y in range(h):
        stack.append((0, y))
        stack.append((w - 1, y))
    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        r, g, b, _ = px[x, y]
        if not (is_felt(r, g, b) or is_wood(r, g, b)):
            continue
        mp[x, y] = 0
        stack.append((x + 1, y))
        stack.append((x - 1, y))
        stack.append((x, y + 1))
        stack.append((x, y - 1))
    # soften by a hair so the cut edge is not a staircase over the painting
    mask = mask.filter(ImageFilter.GaussianBlur(0.6))

    out = Image.new('RGBA', (OUT, OUT), (0, 0, 0, 0))
    card = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    cp, mp = card.load(), mask.load()
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            cp[x, y] = (r, g, b, mp[x, y])
    out.alpha_composite(card, (0, 0))

    kept = sum(1 for y in range(h) for x in range(w) if mp[x, y] > 8)
    print(f'card cut from {CARD}: {w}x{h}, {kept} of {w * h} pixels kept '
          f'({100.0 * kept / (w * h):.0f}% - the rest was table)')
    return out


def write_tga(img, path):
    """Uncompressed 32-bit BGRA, bottom-up, no footer - as the other Media/*.tga are stored."""
    w, h = img.size
    header = bytes([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    w & 0xFF, w >> 8, h & 0xFF, h >> 8, 32, 8])
    px = img.load()
    rows = []
    for y in range(h - 1, -1, -1):
        row = bytearray()
        for x in range(w):
            r, g, b, a = px[x, y]
            row += bytes((b, g, r, a))
        rows.append(bytes(row))
    with open(path, 'wb') as f:
        f.write(header)
        f.write(b''.join(rows))


TILT = 30.0     # degrees the painted card leans, measured from its own corners


def upright(card):
    """The same card turned straight, for the one that lifts off the pile under the mouse.

    The cards on the table are upright, so the card you draw should be too. Turning it in game
    would crop its corners - the cut has almost no margin inside its box - so it is turned here,
    where the canvas can grow to fit, and the UI just draws the result.
    """
    # PIL turns anticlockwise for a positive angle, which is what undoes this card's lean
    turned = card.rotate(TILT, resample=Image.BICUBIC, expand=True)
    box = turned.getbbox()          # trim back to the card itself
    turned = turned.crop(box)
    if turned.width > OUT or turned.height > OUT:
        turned.thumbnail((OUT, OUT), Image.LANCZOS)
    out = Image.new('RGBA', (OUT, OUT), (0, 0, 0, 0))
    out.alpha_composite(turned, (0, 0))
    return out, turned.size


def main(media):
    img = build(media)
    out = os.path.join(media, 'Deck_Card.tga')
    write_tga(img, out)
    print(f'{out}: {OUT}x{OUT}, {os.path.getsize(out)} bytes')
    print(f'the UI draws it {CARD[2] - CARD[0]} x {CARD[3] - CARD[1]} at the panel\'s '
          f'top left + ({CARD[0]}, -{CARD[1]})')

    up, size = upright(img.crop((0, 0, CARD[2] - CARD[0], CARD[3] - CARD[1])))
    out2 = os.path.join(media, 'Deck_Card_Up.tga')
    write_tga(up, out2)
    print(f'{out2}: {OUT}x{OUT}, turned {TILT:.0f} degrees straight, '
          f'card occupies {size[0]} x {size[1]} (aspect {size[0] / size[1]:.3f})')
    print(f'  -> Lua: UP_W, UP_H = {size[0]}, {size[1]}')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1])
